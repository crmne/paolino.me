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
        body = unwrap_block_paragraphs(body)
        body = remove_empty_paragraphs(body)
        body = apply_content_spacing(body)

        published_at = post.date.getlocal.strftime("%B %-d, %Y")
        escaped_title = CGI.escapeHTML(post.data["title"].to_s)
        escaped_url = CGI.escapeHTML(post_url)
        author_block = author_header_html
        hero_media = post_hero_media_html(post, post_url)
        title_block = text_row_html(escaped_title, font_size: "32px", line_height: "1.2", font_weight: "700", color: "#111827", padding_bottom: "6px")
        date_block = text_row_html(CGI.escapeHTML(published_at), font_size: "14px", line_height: "1.4", color: "#6b7280", padding_bottom: "18px")
        read_link_block = text_row_html(%(<a href="#{escaped_url}" style="color:#2563eb;text-decoration:underline;">Read on paolino.me</a>), font_size: "15px", line_height: "1.5", padding_bottom: "20px")
        continue_link_block = text_row_html(%(<a href="#{escaped_url}" style="color:#2563eb;text-decoration:underline;">Continue reading on paolino.me</a>), font_size: "15px", line_height: "1.5")
        unsubscribe_block = text_row_html(%(If this email is no longer relevant, you can <a href="{{unsubscribe_url}}" style="color:#6b7280;text-decoration:underline;">unsubscribe</a>.), font_size: "12px", line_height: "1.4", color: "#6b7280", padding_top: "14px")

        <<~HTML
          <!doctype html>
          <html>
            <body style="margin:0;padding:20px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111827;line-height:1.65;font-size:16px;">
              #{title_block}
              #{date_block}
              #{author_block}
              #{read_link_block}
              #{hero_media}
              #{body}
              <hr style="border:none;border-top:1px solid #e5e7eb;margin:32px 0;" />
              #{continue_link_block}
              #{unsubscribe_block}
              <!-- source-post: #{escaped_url} -->
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
          source = Regexp.last_match(2)

          if plain_code_language?(language)
            code = plain_code(source)
            email_code_block(code, language)
          else
            code = code_lines_html_with_rouge(source)
            email_code_block(code, language, code_is_html: true)
          end
        end

        content.gsub!(
          %r{<div class="highlighter-rouge">\s*<div class="highlight">\s*<pre class="highlight">\s*<code>(.*?)</code>\s*</pre>\s*</div>\s*</div>}m
        ) do
          code = code_lines_html_with_rouge(Regexp.last_match(1))
          email_code_block(code, nil, code_is_html: true)
        end

        content
      end

      def plain_code_language?(language)
        %w[sh bash shell zsh console plaintext text].include?(language.to_s.downcase)
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

      def unwrap_block_paragraphs(html)
        html.gsub(%r{<p>\s*(<(?:div|table|pre|blockquote|ul|ol|h[1-6])\b.*?</(?:div|table|pre|blockquote|ul|ol|h[1-6])>)\s*</p>}im, '\1')
      end

      def apply_content_spacing(html)
        content = html.dup
        content = convert_blockquotes_to_tables(content)
        content = convert_heading_to_table(content, tag: "h2", font_size: "28px", line_height: "1.25", padding_top: "30px", padding_bottom: "12px")
        content = convert_heading_to_table(content, tag: "h3", font_size: "22px", line_height: "1.3", padding_top: "24px", padding_bottom: "10px")
        content = convert_lists_to_tables(content)
        content = convert_paragraphs_to_tables(content)
        content
      end

      def convert_heading_to_table(html, tag:, font_size:, line_height:, padding_top:, padding_bottom:)
        html.gsub(%r{<#{tag}[^>]*>(.*?)</#{tag}>}im) do
          content = Regexp.last_match(1).to_s.strip
          next "" if content.empty?

          <<~HTML.chomp
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;">
              <tr>
                <td style="padding:#{padding_top} 0 #{padding_bottom};font-size:#{font_size};line-height:#{line_height};font-weight:700;color:#111827;">#{content}</td>
              </tr>
            </table>
          HTML
        end
      end

      def convert_paragraphs_to_tables(html)
        html.gsub(%r{<p[^>]*>(.*?)</p>}im) do
          content = Regexp.last_match(1).to_s.strip
          compact = content.gsub(%r{<br\s*/?>}i, "").gsub("&nbsp;", "").strip
          next "" if compact.empty?

          <<~HTML.chomp
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;">
              <tr>
                <td style="padding:0 0 16px;">#{content}</td>
              </tr>
            </table>
          HTML
        end
      end

      def convert_blockquotes_to_tables(html)
        html.gsub(%r{<blockquote>\s*(.*?)\s*</blockquote>}im) do
          content = Regexp.last_match(1).to_s
          content = content.gsub(%r{</?p[^>]*>}i, "").strip
          next "" if content.empty?

          <<~HTML.chomp
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;">
              <tr>
                <td style="padding:0 0 18px 12px;border-left:3px solid #e5e7eb;color:#374151;">#{content}</td>
              </tr>
            </table>
          HTML
        end
      end

      def convert_lists_to_tables(html)
        html.gsub(%r{<(ul|ol)[^>]*>(.*?)</\1>}im) do
          tag = Regexp.last_match(1)
          list_inner = Regexp.last_match(2).to_s
          lines = list_lines_html(tag, list_inner)
          next "" if lines.empty?

          <<~HTML.chomp
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;">
              <tr>
                <td style="padding:0 0 16px;line-height:1.2;color:#111827;">#{lines}</td>
              </tr>
            </table>
          HTML
        end
      end

      def list_lines_html(tag, inner_html)
        items = inner_html.scan(%r{<li[^>]*>(.*?)</li>}im).flatten.map do |item|
          cleaned = item.to_s.strip
          cleaned = cleaned.gsub(%r{^\s*<p[^>]*>}i, "")
          cleaned = cleaned.gsub(%r{</p>\s*$}i, "")
          cleaned = cleaned.gsub(/\r\n?/, "\n").gsub(/\n+/, " ").gsub(/[ \t]{2,}/, " ")
          cleaned.strip
        end.reject(&:empty?)
        return "" if items.empty?

        ordered = tag.to_s.downcase == "ol"

        items.each_with_index.map do |item, index|
          marker = ordered ? "#{index + 1}." : "&bull;"
          "#{marker} #{item}"
        end.join("<br />")
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

      def email_code_block(code, language, code_is_html: false)
        label = CGI.escapeHTML(code_block_label(language))
        formatted_code = code_is_html ? code : code_lines_html(code)
        content_html =
          if code_is_html
            formatted_code
          else
            %(<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;border-collapse:collapse;">#{code_rows_html(formatted_code)}</table>)
          end
        content_padding = code_is_html ? "10px 12px" : "8px 10px"
        content_line_height = code_is_html ? "1.25" : "1.2"

        <<~HTML.chomp
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;border-collapse:collapse;margin:20px 0;border:1px solid #e5e7eb;">
            <tr>
              <td style="padding:6px 10px;background:#f3f4f6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:11px;line-height:1.2;color:#6b7280;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;">#{label}</td>
            </tr>
            <tr>
              <td style="padding:#{content_padding};background:#fafafa;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,'Liberation Mono','Courier New',monospace;font-size:13px;line-height:#{content_line_height};color:#111827;">#{content_html}</td>
            </tr>
          </table>
        HTML
      end

      def code_block_label(language)
        normalized = language.to_s.strip.downcase
        return "CODE" if normalized.empty?
        return "BASH" if %w[sh bash shell zsh console].include?(normalized)
        return "PLAINTEXT" if %w[plaintext text].include?(normalized)

        normalized.upcase
      end

      def plain_code(fragment)
        stripped = fragment
          .to_s
          .gsub(%r{<span[^>]*>}, "")
          .gsub(%r{</span>}, "")
          .gsub(%r{<[^>]+>}, "")

        CGI.escapeHTML(CGI.unescapeHTML(stripped))
      end

      def code_lines_html(code, collapse_blank_lines: true)
        lines = normalized_code_lines(code, unescape: true, collapse_blank_lines: collapse_blank_lines)
        lines.map { |line| format_code_text_segment(line) }.join("<br />")
      end

      def text_row_html(content, font_size:, line_height:, padding_top: "0", padding_bottom: "0", color: "#111827", font_weight: "400")
        <<~HTML.chomp
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;">
            <tr>
              <td style="padding:#{padding_top} 0 #{padding_bottom};font-size:#{font_size};line-height:#{line_height};color:#{color};font-weight:#{font_weight};">#{content}</td>
            </tr>
          </table>
        HTML
      end

      ROUGE_INLINE_COLOR_STYLES = {
        "k" => "color:#b45309;font-weight:700;",
        "kd" => "color:#b45309;font-weight:700;",
        "kn" => "color:#b45309;font-weight:700;",
        "kp" => "color:#b45309;font-weight:700;",
        "kr" => "color:#b45309;font-weight:700;",
        "kt" => "color:#b45309;font-weight:700;",
        "nb" => "color:#0f766e;",
        "nc" => "color:#1d4ed8;font-weight:700;",
        "nf" => "color:#1d4ed8;font-weight:700;",
        "nn" => "color:#1d4ed8;",
        "no" => "color:#1d4ed8;",
        "sx" => "color:#047857;",
        "s" => "color:#047857;",
        "s1" => "color:#047857;",
        "s2" => "color:#047857;",
        "m" => "color:#2563eb;",
        "mi" => "color:#2563eb;",
        "mf" => "color:#2563eb;",
        "mh" => "color:#2563eb;",
        "mo" => "color:#2563eb;",
        "c" => "color:#6b7280;font-style:italic;",
        "c1" => "color:#6b7280;font-style:italic;",
        "cm" => "color:#6b7280;font-style:italic;",
        "cp" => "color:#6b7280;font-style:italic;",
        "cs" => "color:#6b7280;font-style:italic;",
        "o" => "color:#374151;"
      }.freeze

      def code_lines_html_with_rouge(fragment)
        html = fragment.to_s.gsub("\r\n", "\n")
        html = html.gsub(%r{<span class="([^"]+)">}) do
          classes = Regexp.last_match(1).split(/\s+/)
          style = classes.map { |klass| ROUGE_INLINE_COLOR_STYLES[klass] }.compact.first
          style ? %(<span style="#{style}">) : "<span>"
        end

        has_styled_tokens = html.include?('<span style="')
        lines = normalized_code_lines(html, unescape: false, collapse_blank_lines: !has_styled_tokens)
        lines.map { |line| format_html_code_line(line) }.join("<br />")
      end

      def normalized_code_lines(text, unescape:, collapse_blank_lines:)
        normalized = text.to_s.gsub("\r\n", "\n").sub(/\n\z/, "")
        normalized = CGI.unescapeHTML(normalized) if unescape
        lines = normalized.split("\n", -1)
        lines = trim_blank_code_lines(lines)
        collapse_blank_lines ? collapse_consecutive_blank_code_lines(lines) : lines
      end

      def trim_blank_code_lines(lines)
        trimmed = lines.drop_while { |line| line.strip.empty? }
        trimmed.reverse.drop_while { |line| line.strip.empty? }.reverse
      end

      def collapse_consecutive_blank_code_lines(lines)
        collapsed = []
        previous_blank = false

        lines.each do |line|
          blank = line.strip.empty?
          next if blank && previous_blank

          collapsed << line
          previous_blank = blank
        end

        collapsed
      end

      def format_html_code_line(line)
        line.split(%r{(<[^>]+>)}).map do |segment|
          if segment.start_with?("<") && segment.end_with?(">")
            segment
          else
            format_code_text_segment(segment)
          end
        end.join
      end

      def format_code_text_segment(text)
        escaped = CGI.escapeHTML(CGI.unescapeHTML(text.to_s)).gsub("\t", "  ")
        escaped = escaped.gsub(/\A +/) { |run| "&nbsp;" * run.length }
        escaped.gsub(/ {2,}/) { |run| " " + ("&nbsp;" * (run.length - 1)) }
      end

      def code_rows_html(formatted_code)
        lines = formatted_code.to_s.split(%r{<br\s*/?>}, -1)
        lines = trim_blank_code_lines(lines)
        lines = [""] if lines.empty?

        lines.map do |line|
          padding_bottom = "0"
          content = line.empty? ? "&nbsp;" : line

          <<~HTML.chomp
            <tr>
              <td style="padding:0 0 #{padding_bottom};line-height:1.1;">#{content}</td>
            </tr>
          HTML
        end.join
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
            %(<img src="#{escaped_avatar}" alt="#{escaped_name}" width="42" height="42" style="display:block;width:42px;height:42px;border-radius:999px;" />)
          end

        <<~HTML.chomp
          <table role="presentation" cellspacing="0" cellpadding="0" style="margin:0 0 18px;">
            <tr>
              <td style="vertical-align:middle;padding-bottom:14px;">#{avatar_html}</td>
              <td style="vertical-align:middle;padding-left:10px;padding-bottom:14px;font-size:14px;color:#111827;font-weight:600;">#{escaped_name}</td>
            </tr>
          </table>
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
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;margin:0 0 24px;">
            <tr>
              <td>
                <a href="#{escaped_post_url}" style="text-decoration:none;">
                  <img src="#{escaped_image}" alt="#{escaped_title}" style="display:block;width:100%;height:auto;border-radius:10px;" />
                </a>
              </td>
            </tr>
          </table>
        HTML
      end

      def media_preview_card(post_url, preview_image_url, label, link_url: nil, play_overlay: false)
        resolved_link_url = link_url.to_s.strip.empty? ? post_url : link_url
        escaped_link_url = CGI.escapeHTML(resolved_link_url)
        escaped_post_url = CGI.escapeHTML(post_url)
        escaped_label = CGI.escapeHTML(label)

        image_html =
          if preview_image_url.to_s.strip.empty?
            ""
          else
            escaped_image = CGI.escapeHTML(preview_image_url)
            %(<a href="#{escaped_link_url}" style="text-decoration:none;"><img src="#{escaped_image}" alt="#{escaped_label}" style="display:block;width:100%;height:auto;border-radius:10px;" /></a>)
          end

        <<~HTML.chomp
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;margin:0 0 8px;">
            <tr>
              <td>#{image_html}</td>
            </tr>
          </table>
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;margin:0 0 24px;">
            <tr>
              <td style="font-size:14px;"><a href="#{escaped_link_url}" style="color:#2563eb;text-decoration:underline;">#{escaped_label}</a><span style="color:#6b7280;"> · </span><a href="#{escaped_post_url}" style="color:#6b7280;text-decoration:underline;">open post</a></td>
            </tr>
          </table>
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
            %(<a href="#{escaped_link_url}" style="text-decoration:none;"><img src="#{escaped_image}" alt="#{escaped_label}" style="display:block;max-width:100%;height:auto;border-radius:10px;" /></a>)
          end

        <<~HTML.chomp
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;margin:0 0 8px;">
            <tr>
              <td>#{image_html}</td>
            </tr>
          </table>
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;margin:0 0 24px;">
            <tr>
              <td style="font-size:14px;"><a href="#{escaped_link_url}" style="color:#2563eb;text-decoration:underline;">#{escaped_label}</a><span style="color:#6b7280;"> · </span><a href="#{escaped_post_url}" style="color:#6b7280;text-decoration:underline;">open post</a></td>
            </tr>
          </table>
        HTML
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
