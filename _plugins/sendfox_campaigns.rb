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
        "post_scope" => "latest",
        "max_pages" => 5,
        "dry_run" => false,
        "update_existing_draft" => false,
        "fail_build" => false
      }.freeze

      CAMPAIGN_MARKER_PREFIX = "SFPOST".freeze
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
        @fail_build = truthy?(@config["fail_build"]) || truthy?(ENV["SENDFOX_FAIL_BUILD"])
      end

      def publish
        return unless enabled?
        return unless environment_allowed?

        unless configured?
          log_info("Skipped (missing SENDFOX_API_TOKEN / SENDFOX_FROM_NAME / SENDFOX_FROM_EMAIL)")
          return
        end

        previews = campaign_previews
        if previews.empty?
          log_info("Skipped (no published posts)")
          return
        end

        campaign_pool = @dry_run ? [] : list_campaigns
        stats = { created: 0, updated: 0, skipped: 0, dry_run: 0 }

        previews.each do |preview|
          result = sync_preview(preview, campaign_pool)
          stats[result] += 1 if stats.key?(result)
        rescue StandardError => e
          log_error("Failed to sync '#{preview.fetch(:post).data["title"]}': #{e.message}")
          raise if @fail_build
        end

        log_info(
          "Sync complete (scope=#{post_scope}, posts=#{previews.length}, created=#{stats[:created]}, updated=#{stats[:updated]}, skipped=#{stats[:skipped]}, dry_run=#{stats[:dry_run]})"
        )
      rescue StandardError => e
        log_error("Failed to sync draft campaigns: #{e.message}")
        raise if @fail_build
      end

      def campaign_preview
        previews = campaign_previews
        return nil if previews.empty?

        previews.last
      end

      def campaign_previews
        posts = scoped_posts
        return [] if posts.empty?

        posts.map { |post| campaign_preview_for(post) }
      end

      private

      def campaign_preview_for(post)
        post_url = absolute_post_url(post.url)
        campaign_key = campaign_key_for(post_url)
        campaign_title = campaign_title_for(post.data["title"].to_s, campaign_key)
        subject = truncate(post.data["title"].to_s, MAX_SUBJECT_LENGTH)

        {
          post: post,
          post_url: post_url,
          campaign_key: campaign_key,
          campaign_title: campaign_title,
          configured_campaign_id: configured_campaign_id_for(post),
          payload: {
            title: campaign_title,
            subject: subject,
            html: newsletter_html(post, post_url),
            from_name: @from_name,
            from_email: @from_email
          }
        }
      end

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
        published_posts.max_by(&:date)
      end

      def published_posts
        now = Time.now
        @site.posts.docs.reject { |post| draft?(post) || post.date > now }
      end

      def scoped_posts
        posts = published_posts
        return [] if posts.empty?

        return [posts.max_by(&:date)] if post_scope == "latest"

        posts.sort_by(&:date)
      end

      def post_scope
        raw = @config["post_scope"].to_s.strip.downcase
        return "all" if raw == "all"

        "latest"
      end

      def draft?(post)
        truthy?(post.data["draft"])
      end

      def campaign_key_for(post_url)
        Digest::SHA256.hexdigest(post_url)[0, 10]
      end

      def campaign_marker_for(campaign_key)
        "[#{CAMPAIGN_MARKER_PREFIX}:#{campaign_key}]"
      end

      def legacy_campaign_marker_for(campaign_key)
        "[#{campaign_key}]"
      end

      def campaign_title_for(post_title, campaign_key)
        marker = campaign_marker_for(campaign_key)
        base_title = "#{@campaign_prefix}: #{post_title}"
        max_base_length = MAX_TITLE_LENGTH - marker.length - 1
        truncated_base = truncate(base_title, max_base_length)
        "#{truncated_base} #{marker}".strip
      end

      def configured_campaign_id_for(post)
        value = post.data["sendfox_campaign_id"]
        value = post.data.dig("sendfox", "campaign_id") if value.nil? && post.data["sendfox"].is_a?(Hash)

        id = Integer(value, exception: false)
        return nil unless id&.positive?

        id
      end

      def list_campaigns
        campaigns = []
        page = 1

        loop do
          response = request_json(
            method: :get,
            path: "/campaigns",
            query: { page: page },
            expected_statuses: [200]
          )

          page_campaigns = Array(response["data"])
          campaigns.concat(page_campaigns)

          break if page_campaigns.empty?
          break if page >= @max_pages

          per_page = response["per_page"].to_i
          total = response["total"].to_i
          break if per_page.positive? && total.positive? && (page * per_page) >= total
          break if per_page.positive? && page_campaigns.length < per_page

          page += 1
        end

        campaigns
      end

      def sync_preview(preview, campaign_pool)
        campaign_title = preview.fetch(:campaign_title)
        payload = preview.fetch(:payload)

        if @dry_run
          log_info("Dry run: would create or update draft '#{campaign_title}'")
          return :dry_run
        end

        existing_campaign = find_existing_campaign(preview, campaign_pool)
        if existing_campaign
          return handle_existing_campaign(existing_campaign, preview, payload)
        end

        response = request_json(
          method: :post,
          path: "/campaigns",
          payload: payload,
          expected_statuses: [201]
        )
        campaign_pool << response if response.is_a?(Hash)

        log_info("Draft campaign created (id=#{response["id"]}, title='#{campaign_title}')")
        :created
      end

      def find_existing_campaign(preview, campaign_pool)
        campaign_id = preview[:configured_campaign_id]
        if campaign_id
          campaign = find_campaign_by_id(campaign_id, campaign_pool)
          return campaign if campaign
        end

        matches = campaign_pool.select { |campaign| campaign_matches_preview?(campaign, preview) }
        matches.find { |campaign| draft_campaign?(campaign) } || matches.first
      end

      def find_campaign_by_id(campaign_id, campaign_pool)
        campaign = campaign_pool.find { |item| item["id"].to_i == campaign_id.to_i }
        return campaign if campaign

        request_json(
          method: :get,
          path: "/campaigns/#{campaign_id}",
          expected_statuses: [200]
        )
      rescue StandardError => e
        log_error("Failed to fetch configured campaign id=#{campaign_id}: #{e.message}")
        nil
      end

      def campaign_matches_preview?(campaign, preview)
        campaign_key = preview.fetch(:campaign_key)
        title = campaign["title"].to_s
        return true if title.include?(campaign_marker_for(campaign_key))
        return true if title.end_with?(legacy_campaign_marker_for(campaign_key))

        source_url = source_post_url_from_html(campaign["html"])
        return false if source_url.to_s.strip.empty?

        normalize_url(source_url) == normalize_url(preview.fetch(:post_url))
      end

      def source_post_url_from_html(html)
        match = html.to_s.match(/source-post:\s*([^\s<]+)/i)
        return nil unless match

        match[1]
      end

      def normalize_url(url)
        url.to_s.sub(%r{/$}, "")
      end

      def handle_existing_campaign(existing_campaign, preview, payload)
        campaign_title = preview.fetch(:campaign_title)

        unless truthy?(@config["update_existing_draft"])
          log_info("Skipped (campaign already exists: '#{campaign_title}')")
          return :skipped
        end

        unless draft_campaign?(existing_campaign)
          log_info("Skipped (campaign already sent: '#{campaign_title}')")
          return :skipped
        end

        campaign_id = existing_campaign["id"]
        if campaign_id.to_s.strip.empty?
          log_info("Skipped (existing campaign has no id: '#{campaign_title}')")
          return :skipped
        end

        response = request_json(
          method: :patch,
          path: "/campaigns/#{campaign_id}",
          payload: payload,
          expected_statuses: [200]
        )

        log_info("Draft campaign updated (id=#{response["id"] || campaign_id}, title='#{campaign_title}')")
        :updated
      end

      def draft_campaign?(campaign)
        campaign["sent_at"].to_s.strip.empty?
      end

      def newsletter_html(post, post_url)
        body = post.content.to_s
        body = absolutize_urls(body)
        body = convert_rouge_blocks(body)
        body = convert_plain_code_blocks(body)
        body = remove_inline_rouge_classes(body)
        body = convert_embedded_media(body, post_url)
        body = remove_empty_paragraphs(body)

        published_at = post.date.getlocal.strftime("%B %-d, %Y")
        escaped_title = CGI.escapeHTML(post.data["title"].to_s)
        escaped_url = CGI.escapeHTML(post_url)
        author_block = author_header_html
        hero_media = post_hero_media_html(post, post_url)
        preheader_html = hidden_preheader_html(campaign_preheader_text(post))

        <<~HTML
          <!doctype html>
          <html>
            <body style="margin:0;padding:0;background:#ffffff;">
              #{preheader_html}
              <div style="margin:0 auto;max-width:680px;padding:24px 20px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111827;line-height:1.65;font-size:16px;">
                <h1 style="margin:0 0 8px;font-size:32px;line-height:1.2;color:#111827;">#{escaped_title}</h1>
                <p style="margin:0 0 14px;font-size:14px;color:#6b7280;">#{CGI.escapeHTML(published_at)}</p>
                #{author_block}
                <p style="margin:0 0 24px;font-size:15px;"><a href="#{escaped_url}" style="color:#2563eb;text-decoration:underline;">Read on paolino.me</a></p>
                #{hero_media}
                #{body}
                <hr style="border:none;border-top:1px solid #e5e7eb;margin:32px 0;" />
                <p style="margin:0;font-size:15px;"><a href="#{escaped_url}" style="color:#2563eb;text-decoration:underline;">Continue reading on paolino.me</a></p>
                <p style="margin:14px 0 0;font-size:12px;color:#6b7280;">If this email is no longer relevant, you can <a href="{{unsubscribe_url}}" style="color:#6b7280;text-decoration:underline;">unsubscribe</a>.</p>
                <!-- source-post: #{escaped_url} -->
              </div>
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

      def remove_empty_paragraphs(html)
        html.gsub(%r{<p>\s*(?:<br\s*/?>|\&nbsp;|\s)*</p>}im, "")
      end

      def convert_embedded_media(html, post_url)
        content = html.dup

        content.gsub!(%r{<video\b[^>]*>.*?</video>}im) do |video_tag|
          source_url = source_url_from_video_tag(video_tag)
          poster_url = poster_url_from_video_tag(video_tag)
          preview_image_url = poster_url || preview_image_for_video(source_url, nil)
          inline_media_preview_html(
            post_url,
            preview_image_url,
            "Watch video",
            link_url: media_link_url(source_url, post_url),
            play_overlay: true
          )
        end

        content.gsub!(%r{<iframe\b[^>]*>.*?</iframe>}im) do |iframe_tag|
          source_url = iframe_tag[/\bsrc=(['"])(.*?)\1/i, 2]
          preview_image_url = preview_image_for_video(source_url, nil)
          inline_media_preview_html(
            post_url,
            preview_image_url,
            "Watch media",
            link_url: media_link_url(source_url, post_url),
            play_overlay: true
          )
        end

        content
      end

      def source_url_from_video_tag(video_tag)
        source = video_tag[/<source\b[^>]*\bsrc=(['"])(.*?)\1/i, 2]
        source ||= video_tag[/\bsrc=(['"])(.*?)\1/i, 2]
        absolute_asset_url(source)
      end

      def poster_url_from_video_tag(video_tag)
        poster = video_tag[/\bposter=(['"])(.*?)\1/i, 2]
        absolute_asset_url(poster)
      end

      def email_code_block(code, language)
        label = language.to_s.empty? ? "CODE" : CGI.escapeHTML(language.upcase)

        <<~HTML.chomp
          <div style="margin:24px 0;">
            <p style="margin:0 0 8px;font-size:11px;line-height:1.3;letter-spacing:0.08em;text-transform:uppercase;color:#6b7280;font-weight:700;">#{label}</p>
            <pre style="margin:0;padding:14px 16px;background:#f8fafc;border:1px solid #e5e7eb;border-radius:8px;white-space:pre-wrap;overflow:auto;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,'Liberation Mono','Courier New',monospace;font-size:13px;line-height:1.55;color:#111827;">#{code}</pre>
          </div>
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

      def author_header_html
        author_name = @site.config.dig("author", "name").to_s.strip
        author_name = @from_name.to_s.strip if author_name.empty?
        author_name = "Author" if author_name.empty?

        avatar_path = @site.config.dig("author", "avatar")
        avatar_path = @site.config.dig("author", "image") if avatar_path.to_s.strip.empty?
        avatar_url = absolute_asset_url(avatar_path)
        escaped_name = CGI.escapeHTML(author_name)

        avatar_html =
          if avatar_url.to_s.strip.empty?
            ""
          else
            escaped_avatar = CGI.escapeHTML(avatar_url)
            %(<img src="#{escaped_avatar}" alt="#{escaped_name}" width="42" height="42" style="display:inline-block;vertical-align:middle;width:42px;height:42px;border-radius:999px;border:1px solid #e5e7eb;object-fit:cover;margin-right:10px;" />)
          end

        <<~HTML.chomp
          <p style="margin:0 0 18px;font-size:14px;color:#111827;font-weight:600;line-height:42px;">
            #{avatar_html}<span style="display:inline-block;vertical-align:middle;line-height:1.3;">#{escaped_name}</span>
          </p>
        HTML
      end

      def post_hero_media_html(post, post_url)
        video_url = absolute_asset_url(post.data["video"])
        image_url = primary_post_image_url(post)

        if !video_url.to_s.strip.empty?
          # Prefer explicit post image as the video thumbnail when provided.
          preview_image_url = image_url || preview_image_for_video(video_url, nil)
          return media_preview_card(
            post_url,
            preview_image_url,
            "Watch video",
            link_url: post_url,
            play_overlay: true
          )
        end

        return "" if image_url.to_s.strip.empty?

        escaped_image = CGI.escapeHTML(image_url)
        escaped_post_url = CGI.escapeHTML(post_url)
        escaped_title = CGI.escapeHTML(post.data["title"].to_s)

        <<~HTML.chomp
          <p style="margin:0 0 24px;">
            <a href="#{escaped_post_url}" style="text-decoration:none;">
              <img src="#{escaped_image}" alt="#{escaped_title}" style="display:block;width:100%;height:auto;border-radius:10px;" />
            </a>
          </p>
        HTML
      end

      def media_preview_card(post_url, preview_image_url, label, link_url: nil, play_overlay: false)
        resolved_link_url = link_url.to_s.strip.empty? ? post_url : link_url
        escaped_link_url = CGI.escapeHTML(resolved_link_url)
        escaped_post_url = CGI.escapeHTML(post_url)
        escaped_label = CGI.escapeHTML(label)

        image_row =
          if preview_image_url.to_s.strip.empty?
            ""
          else
            escaped_image = CGI.escapeHTML(preview_image_url)
            <<~HTML.chomp
              <a href="#{escaped_link_url}" style="text-decoration:none;display:block;position:relative;">
                <img src="#{escaped_image}" alt="#{escaped_label}" style="display:block;width:100%;height:auto;border-radius:10px;" />
                #{play_overlay ? media_play_overlay_html : ""}
              </a>
            HTML
          end

        <<~HTML.chomp
          <div style="margin:0 0 24px;">
            #{image_row}
            <p style="margin:10px 0 0;font-size:14px;">
              <a href="#{escaped_link_url}" style="color:#2563eb;text-decoration:underline;">#{escaped_label}</a>
              <span style="color:#6b7280;"> · </span>
              <a href="#{escaped_post_url}" style="color:#6b7280;text-decoration:underline;">open post</a>
            </p>
          </div>
        HTML
      end

      def inline_media_preview_html(post_url, preview_image_url, label, link_url: nil, play_overlay: false)
        resolved_link_url = link_url.to_s.strip.empty? ? post_url : link_url
        escaped_link_url = CGI.escapeHTML(resolved_link_url)
        escaped_post_url = CGI.escapeHTML(post_url)
        escaped_label = CGI.escapeHTML(label)

        image_html =
          if preview_image_url.to_s.strip.empty?
            ""
          else
            escaped_image = CGI.escapeHTML(preview_image_url)
            <<~HTML.chomp
              <a href="#{escaped_link_url}" style="text-decoration:none;display:block;position:relative;">
                <img src="#{escaped_image}" alt="#{escaped_label}" style="display:block;max-width:100%;height:auto;border-radius:10px;" />
                #{play_overlay ? media_play_overlay_html : ""}
              </a>
            HTML
          end

        <<~HTML.chomp
          <div style="margin:20px 0;">
            #{image_html}
            <p style="margin:10px 0 0;font-size:14px;">
              <a href="#{escaped_link_url}" style="color:#2563eb;text-decoration:underline;">#{escaped_label}</a>
              <span style="color:#6b7280;"> · </span>
              <a href="#{escaped_post_url}" style="color:#6b7280;text-decoration:underline;">open post</a>
            </p>
          </div>
        HTML
      end

      def media_play_overlay_html
        <<~HTML.chomp
          <span style="position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:68px;height:68px;line-height:68px;text-align:center;border-radius:999px;background:rgba(17,24,39,0.72);color:#ffffff;font-size:30px;font-weight:700;">&#9658;</span>
        HTML
      end

      def campaign_preheader_text(post)
        text = post.data["description"]
        text = post.data["excerpt"] if text.to_s.strip.empty?
        text = post.excerpt.to_s if text.to_s.strip.empty?
        normalized_plain_text(text, 220)
      end

      def hidden_preheader_html(text)
        value = text.to_s.strip
        return "" if value.empty?

        escaped = CGI.escapeHTML(value)
        filler = Array.new(24, "&#847;").join

        <<~HTML.chomp
          <div style="display:none;font-size:1px;color:#ffffff;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;">#{escaped}#{filler}</div>
        HTML
      end

      def normalized_plain_text(fragment, max_length)
        plain = fragment.to_s
          .gsub(%r{<[^>]+>}, " ")
          .gsub(/&nbsp;/i, " ")
          .gsub(/\s+/, " ")
          .strip

        truncate(plain, max_length)
      end

      def preview_image_for_video(video_url, fallback_image_url)
        youtube_id = youtube_video_id(video_url)
        return "https://img.youtube.com/vi/#{youtube_id}/hqdefault.jpg" if youtube_id

        fallback_image_url
      end

      def media_link_url(source_url, fallback_url)
        return fallback_url if source_url.to_s.strip.empty?

        youtube_id = youtube_video_id(source_url)
        return "https://www.youtube.com/watch?v=#{youtube_id}" if youtube_id

        source_url
      end

      def youtube_video_id(url)
        value = url.to_s
        return nil if value.strip.empty?

        return Regexp.last_match(1) if value.match(%r{youtu\.be/([A-Za-z0-9_-]{6,})}i)
        return Regexp.last_match(1) if value.match(%r{youtube\.com/embed/([A-Za-z0-9_-]{6,})}i)
        return Regexp.last_match(1) if value.match(%r{[?&]v=([A-Za-z0-9_-]{6,})}i)

        nil
      end

      def primary_post_image_url(post)
        image = post.data["image"]
        value =
          if image.is_a?(Hash)
            image["path"] || image["url"]
          else
            image
          end

        absolute_asset_url(value)
      end

      def absolute_post_url(path)
        absolute = absolute_site_prefix
        return path if absolute.empty?

        "#{absolute}#{path}"
      end

      def absolute_asset_url(raw_path)
        value = raw_path.to_s.strip
        return nil if value.empty?
        return value if value.match?(%r{\Ahttps?://}i)

        value = "/#{value}" unless value.start_with?("/")

        prefix = absolute_site_prefix
        return value if prefix.empty?

        "#{prefix}#{value}"
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
          when :patch
            Net::HTTP::Patch.new(uri)
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
