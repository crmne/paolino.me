# frozen_string_literal: true

require "cgi"
require "digest"
require "json"
require "net/http"
require "time"
require "uri"

module Jekyll
  module SendfoxCampaigns
    class Publisher
      DEFAULTS = {
        "enabled" => true,
        "skip_in_development" => true,
        "api_base_url" => "https://api.sendfox.com",
        "campaign_prefix" => nil,
        "max_pages" => 5,
        "dry_run" => false,
        "fail_build" => false
      }.freeze

      MAX_TITLE_LENGTH = 191
      MAX_SUBJECT_LENGTH = 191

      def self.publish(site)
        new(site).publish
      end

      def initialize(site)
        @site = site
        @config = build_config
        @api_base_url = @config.fetch("api_base_url")
        @campaign_prefix = @config["campaign_prefix"] || site.config["title"] || "Newsletter"
        @api_token = env("SENDFOX_API_TOKEN")
        @from_name = env("SENDFOX_FROM_NAME", @config["from_name"], site.config.dig("author", "name"))
        @from_email = env("SENDFOX_FROM_EMAIL", @config["from_email"])
        @max_pages = positive_int(@config["max_pages"], fallback: 5)
        @dry_run = truthy?(@config["dry_run"]) || truthy?(ENV["SENDFOX_DRY_RUN"])
      end

      def publish
        return unless enabled?
        return unless environment_allowed?

        unless configured?
          log_info("Skipped (missing SENDFOX_API_TOKEN / SENDFOX_FROM_NAME / SENDFOX_FROM_EMAIL)")
          return
        end

        post = latest_published_post
        unless post
          log_info("Skipped (no published posts)")
          return
        end

        post_url = absolute_post_url(post.url)
        campaign_title = campaign_title_for(post.data["title"].to_s, post_url)
        subject = truncate(post.data["title"].to_s, MAX_SUBJECT_LENGTH)
        html = newsletter_html(post, post_url)

        if @dry_run
          log_info("Dry run: would create draft '#{campaign_title}'")
          return
        end

        if campaign_exists?(campaign_title)
          log_info("Skipped (draft already exists: '#{campaign_title}')")
          return
        end

        payload = {
          title: campaign_title,
          subject: subject,
          html: html,
          from_name: @from_name,
          from_email: @from_email
        }

        response = request_json(
          method: :post,
          path: "/campaigns",
          payload: payload,
          expected_statuses: [201]
        )

        log_info("Draft campaign created (id=#{response["id"]}, title='#{campaign_title}')")
      rescue StandardError => e
        log_error("Failed to create draft campaign: #{e.message}")
        raise if truthy?(@config["fail_build"])
      end

      private

      def build_config
        raw = @site.config["sendfox_campaigns"]
        plugin_config = raw.is_a?(Hash) ? raw : {}
        DEFAULTS.merge(plugin_config)
      end

      def enabled?
        truthy?(@config["enabled"])
      end

      def environment_allowed?
        return true unless truthy?(@config["skip_in_development"])

        Jekyll.env != "development"
      end

      def configured?
        return true if @dry_run

        [@api_token, @from_name, @from_email].all? { |value| !value.to_s.strip.empty? }
      end

      def latest_published_post
        now = Time.now
        posts = @site.posts.docs.reject { |post| draft?(post) || post.date > now }
        posts.max_by(&:date)
      end

      def draft?(post)
        truthy?(post.data["draft"])
      end

      def campaign_title_for(post_title, post_url)
        digest = Digest::SHA256.hexdigest(post_url)[0, 10]
        raw = "#{@campaign_prefix}: #{post_title} [#{digest}]"
        truncate(raw, MAX_TITLE_LENGTH)
      end

      def campaign_exists?(campaign_title)
        page = 1

        loop do
          response = request_json(
            method: :get,
            path: "/campaigns",
            query: { page: page },
            expected_statuses: [200]
          )

          campaigns = Array(response["data"])
          return true if campaigns.any? { |campaign| campaign["title"].to_s.strip == campaign_title }
          break if campaigns.empty?
          break if page >= @max_pages

          per_page = response["per_page"].to_i
          total = response["total"].to_i
          break if per_page.positive? && total.positive? && (page * per_page) >= total
          break if per_page.positive? && campaigns.length < per_page

          page += 1
        end

        false
      end

      def newsletter_html(post, post_url)
        body = post.content.to_s
        body = absolutize_urls(body)
        body = convert_rouge_blocks(body)
        body = convert_plain_code_blocks(body)
        body = remove_inline_rouge_classes(body)

        published_at = post.date.getlocal.strftime("%B %-d, %Y")
        escaped_title = CGI.escapeHTML(post.data["title"].to_s)
        escaped_url = CGI.escapeHTML(post_url)

        <<~HTML
          <!doctype html>
          <html>
            <body style="margin:0;padding:0;background:#f3f4f6;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f3f4f6;padding:24px 0;">
                <tr>
                  <td align="center">
                    <table role="presentation" width="680" cellspacing="0" cellpadding="0" style="width:680px;max-width:680px;background:#ffffff;border:1px solid #e5e7eb;border-radius:12px;">
                      <tr>
                        <td style="padding:32px 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111827;line-height:1.65;font-size:16px;">
                          <p style="margin:0 0 12px;font-size:13px;color:#6b7280;">New post from #{CGI.escapeHTML(@campaign_prefix.to_s)}</p>
                          <h1 style="margin:0 0 8px;font-size:32px;line-height:1.2;color:#111827;">#{escaped_title}</h1>
                          <p style="margin:0 0 24px;font-size:14px;color:#6b7280;">#{CGI.escapeHTML(published_at)}</p>
                          <p style="margin:0 0 24px;font-size:15px;"><a href="#{escaped_url}" style="color:#2563eb;text-decoration:underline;">Read on paolino.me</a></p>
                          #{body}
                          <hr style="border:none;border-top:1px solid #e5e7eb;margin:32px 0;" />
                          <p style="margin:0;font-size:15px;"><a href="#{escaped_url}" style="color:#2563eb;text-decoration:underline;">Continue reading on paolino.me</a></p>
                          <!-- source-post: #{escaped_url} -->
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
            </body>
          </html>
        HTML
      end

      def absolutize_urls(html)
        site_prefix = absolute_site_prefix
        return html if site_prefix.empty?

        content = html.gsub(%r{(href|src)=(['"])/(?!/)([^'"]+)\2}) do
          attr = Regexp.last_match(1)
          quote = Regexp.last_match(2)
          path = Regexp.last_match(3)
          %(#{attr}=#{quote}#{site_prefix}/#{path}#{quote})
        end

        content.gsub(%r{(href|src)=(['"])https?://(?:localhost|127\.0\.0\.1):\d+(/[^'"]*)\2}) do
          attr = Regexp.last_match(1)
          quote = Regexp.last_match(2)
          path = Regexp.last_match(3)
          %(#{attr}=#{quote}#{site_prefix}#{path}#{quote})
        end
      end

      def convert_rouge_blocks(html)
        content = html.dup

        content.gsub!(
          %r{<div class="language-([A-Za-z0-9_+\-]+)\s+highlighter-rouge">\s*<div class="highlight">\s*<pre class="highlight">\s*<code>(.*?)</code>\s*</pre>\s*</div>\s*</div>}m
        ) do
          language = Regexp.last_match(1)
          code = plain_code(Regexp.last_match(2))
          email_code_block(code, language)
        end

        content.gsub!(
          %r{<div class="highlighter-rouge">\s*<div class="highlight">\s*<pre class="highlight">\s*<code>(.*?)</code>\s*</pre>\s*</div>\s*</div>}m
        ) do
          code = plain_code(Regexp.last_match(1))
          email_code_block(code, nil)
        end

        content
      end

      def convert_plain_code_blocks(html)
        html.gsub(%r{<pre><code(?: class="language-([^"]+)")?>(.*?)</code></pre>}m) do
          language = Regexp.last_match(1)
          code = plain_code(Regexp.last_match(2))
          email_code_block(code, language)
        end
      end

      def remove_inline_rouge_classes(html)
        html.gsub(%r{<code class="[^"]*highlighter-rouge[^"]*">}, "<code>")
      end

      def email_code_block(code, language)
        label = language.to_s.empty? ? "CODE" : CGI.escapeHTML(language.upcase)

        <<~HTML.chomp
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;border-collapse:collapse;margin:24px 0;background:#0f172a;border-radius:10px;overflow:hidden;">
            <tr>
              <td style="padding:7px 12px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.3;color:#cbd5e1;background:#111827;border-bottom:1px solid #1f2937;">#{label}</td>
            </tr>
            <tr>
              <td style="padding:14px 16px;">
                <code style="display:block;white-space:pre-wrap;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,'Liberation Mono','Courier New',monospace;font-size:13px;line-height:1.55;color:#e5e7eb;">#{code}</code>
              </td>
            </tr>
          </table>
        HTML
      end

      def plain_code(fragment)
        stripped = fragment
          .to_s
          .gsub(%r{<span[^>]*>}, "")
          .gsub(%r{</span>}, "")
          .gsub(%r{<[^>]+>}, "")

        CGI.escapeHTML(CGI.unescapeHTML(stripped))
      end

      def absolute_post_url(path)
        absolute = absolute_site_prefix
        return path if absolute.empty?

        "#{absolute}#{path}"
      end

      def absolute_site_prefix
        site_url = @site.config["url"].to_s.sub(%r{/$}, "")
        baseurl = @site.config["baseurl"].to_s
        baseurl = "" if baseurl == "/"
        baseurl = "/#{baseurl}" unless baseurl.empty? || baseurl.start_with?("/")

        "#{site_url}#{baseurl}"
      end

      def request_json(method:, path:, query: nil, payload: nil, expected_statuses:)
        uri = build_uri(path, query)
        request = build_request(method, uri, payload)
        response = perform_request(uri, request)
        status = response.code.to_i

        unless expected_statuses.include?(status)
          raise "SendFox API #{method.to_s.upcase} #{uri} failed (#{response.code}): #{response.body}"
        end

        return {} if response.body.to_s.strip.empty?

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise "Invalid JSON from SendFox API #{method.to_s.upcase} #{uri}: #{e.message}"
      end

      def build_uri(path, query)
        uri = URI.join(@api_base_url, path)
        uri.query = URI.encode_www_form(query) if query && !query.empty?
        uri
      end

      def build_request(method, uri, payload)
        request =
          case method
          when :get
            Net::HTTP::Get.new(uri)
          when :post
            Net::HTTP::Post.new(uri)
          else
            raise "Unsupported HTTP method: #{method}"
          end

        request["Authorization"] = "Bearer #{@api_token}"
        if payload
          request["Content-Type"] = "application/json"
          request.body = JSON.dump(payload)
        end
        request
      end

      def perform_request(uri, request)
        Net::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: 10,
          read_timeout: 30
        ) { |http| http.request(request) }
      end

      def truncate(text, max_length)
        return text if text.length <= max_length

        text.each_char.take(max_length).join
      end

      def positive_int(value, fallback:)
        parsed = Integer(value, exception: false)
        return fallback unless parsed&.positive?

        parsed
      end

      def truthy?(value)
        %w[1 true yes on].include?(value.to_s.strip.downcase)
      end

      def env(*keys)
        keys.each do |key|
          next if key.nil?

          value = ENV[key.to_s]
          return value unless value.to_s.strip.empty?
        end
        nil
      end

      def log_info(message)
        Jekyll.logger.info("SendFox:", message)
      end

      def log_error(message)
        Jekyll.logger.error("SendFox:", message)
      end
    end
  end
end

Jekyll::Hooks.register :site, :post_write do |site|
  Jekyll::SendfoxCampaigns::Publisher.publish(site)
end
