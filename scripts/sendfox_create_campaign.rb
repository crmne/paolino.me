#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "digest"
require "json"
require "net/http"
require "rexml/document"
require "time"
require "uri"

class SendfoxDraftCampaignCreator
  API_BASE_URL = ENV.fetch("SENDFOX_BASE_URL", "https://api.sendfox.com")
  FEED_PATH = ENV.fetch("SENDFOX_FEED_PATH", "_site/rss.xml")
  SITE_URL = ENV.fetch("SITE_URL", "https://paolino.me")
  CAMPAIGN_PREFIX = ENV.fetch("SENDFOX_CAMPAIGN_PREFIX", "paolino.me")
  MAX_CAMPAIGN_TITLE_LENGTH = 191
  MAX_SUBJECT_LENGTH = 191

  def initialize
    @token = ENV["SENDFOX_API_TOKEN"].to_s.strip
    @from_name = ENV["SENDFOX_FROM_NAME"].to_s.strip
    @from_email = ENV["SENDFOX_FROM_EMAIL"].to_s.strip
    @dry_run = truthy?(ENV["SENDFOX_DRY_RUN"])
    @max_pages = parse_positive_int(ENV["SENDFOX_MAX_PAGES"], default: 5)
  end

  def run
    unless configured?
      puts "SendFox draft creation skipped: missing required env vars."
      puts "Required: SENDFOX_API_TOKEN, SENDFOX_FROM_NAME, SENDFOX_FROM_EMAIL"
      return
    end

    post = latest_published_post
    raise "No published posts found in #{FEED_PATH}" unless post

    campaign_title = build_campaign_title(post[:title], post[:url])
    subject = truncate(post[:title], MAX_SUBJECT_LENGTH)
    html = build_email_html(post)

    if @dry_run
      puts "Dry run: campaign would be created with:"
      puts JSON.pretty_generate(
        title: campaign_title,
        subject: subject,
        post_url: post[:url],
        html_preview: html[0, 500]
      )
      return
    end

    if campaign_exists?(campaign_title)
      puts "SendFox draft already exists for '#{campaign_title}'. Nothing to do."
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

    campaign_id = response["id"]
    puts "Created SendFox draft campaign #{campaign_id} for post '#{post[:title]}'."
  end

  private

  def configured?
    @dry_run || [@token, @from_name, @from_email].all? { |v| !v.empty? }
  end

  def latest_published_post
    raise "Feed file not found: #{FEED_PATH}" unless File.exist?(FEED_PATH)

    doc = REXML::Document.new(File.read(FEED_PATH))
    now = Time.now
    posts = []

    doc.elements.each("rss/channel/item") do |item|
      post = extract_post(item)
      next unless post
      next if post[:published_at] > now

      posts << post
    end

    posts.max_by { |post| post[:published_at] }
  end

  def extract_post(item)
    title = text_for(item, "title")
    url = text_for(item, "link")
    pub_date = text_for(item, "pubDate")
    html = content_for(item)

    return nil if [title, url, pub_date, html].any? { |v| v.to_s.strip.empty? }

    {
      title: title.strip,
      url: normalize_post_url(url.strip),
      published_at: Time.rfc2822(pub_date),
      html: html.strip
    }
  rescue ArgumentError
    nil
  end

  def text_for(item, name)
    item.elements[name]&.text.to_s
  end

  def content_for(item)
    encoded_element = item.elements.find { |el| el.expanded_name == "content:encoded" }
    if encoded_element
      encoded = encoded_element.children.map(&:to_s).join
      return encoded unless encoded.strip.empty?
    end

    text_for(item, "description")
  end

  def build_campaign_title(post_title, post_url)
    marker = Digest::SHA256.hexdigest(post_url)[0, 10]
    truncate("#{CAMPAIGN_PREFIX}: #{post_title} [#{marker}]", MAX_CAMPAIGN_TITLE_LENGTH)
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

  def build_email_html(post)
    post_body = absolutize_urls(post[:html])
    post_body = convert_code_blocks_for_email(post_body)
    post_body = style_inline_code(post_body)
    published_label = post[:published_at].getlocal.strftime("%B %-d, %Y")
    post_url = CGI.escapeHTML(post[:url])

    <<~HTML
      <!doctype html>
      <html>
        <body style="margin:0;padding:0;background-color:#f3f4f6;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color:#f3f4f6;padding:24px 0;">
            <tr>
              <td align="center">
                <table role="presentation" width="680" cellspacing="0" cellpadding="0" style="width:680px;max-width:680px;background:#ffffff;border:1px solid #e5e7eb;border-radius:12px;">
                  <tr>
                    <td style="padding:32px 36px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111827;line-height:1.65;font-size:16px;">
                      <p style="margin:0 0 12px;font-size:13px;color:#6b7280;">New post from #{CGI.escapeHTML(CAMPAIGN_PREFIX)}</p>
                      <h1 style="margin:0 0 8px;font-size:32px;line-height:1.2;color:#111827;">#{CGI.escapeHTML(post[:title])}</h1>
                      <p style="margin:0 0 24px;font-size:14px;color:#6b7280;">#{CGI.escapeHTML(published_label)}</p>
                      <p style="margin:0 0 24px;font-size:15px;"><a href="#{post_url}" style="color:#2563eb;text-decoration:underline;">Read on paolino.me</a></p>
                      #{post_body}
                      <hr style="border:none;border-top:1px solid #e5e7eb;margin:32px 0;" />
                      <p style="margin:0;font-size:15px;"><a href="#{post_url}" style="color:#2563eb;text-decoration:underline;">Continue reading on paolino.me</a></p>
                      <!-- source-post: #{post[:url]} -->
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
    normalized_site_url = SITE_URL.sub(%r{/$}, "")
    content = html.gsub(%r{(href|src)=(['"])/(?!/)([^'"]+)\2}) do
      attr = Regexp.last_match(1)
      quote = Regexp.last_match(2)
      path = Regexp.last_match(3)
      %(#{attr}=#{quote}#{normalized_site_url}/#{path}#{quote})
    end

    content.gsub(%r{(href|src)=(['"])https?://(?:localhost|127\.0\.0\.1):\d+(/[^'"]*)\2}) do
      attr = Regexp.last_match(1)
      quote = Regexp.last_match(2)
      path = Regexp.last_match(3)
      %(#{attr}=#{quote}#{normalized_site_url}#{path}#{quote})
    end
  end

  def normalize_post_url(url)
    return url if url.empty?

    normalized_site_url = SITE_URL.sub(%r{/$}, "")
    uri = URI.parse(url)
    return url unless %w[localhost 127.0.0.1].include?(uri.host)

    "#{normalized_site_url}#{uri.path}"
  rescue URI::InvalidURIError
    url
  end

  def convert_code_blocks_for_email(html)
    html.gsub(%r{<pre><code(?: class="language-([^"]+)")?>(.*?)</code></pre>}m) do
      language = Regexp.last_match(1)
      code = Regexp.last_match(2).to_s.strip
      label = language ? CGI.escapeHTML(language.upcase) : "CODE"

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
  end

  def style_inline_code(html)
    html.gsub(%r{<code>(.*?)</code>}m) do
      content = Regexp.last_match(1)
      %(<code style="font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,'Liberation Mono','Courier New',monospace;font-size:0.92em;background:#f3f4f6;padding:2px 4px;border-radius:4px;">#{content}</code>)
    end
  end

  def request_json(method:, path:, query: nil, payload: nil, expected_statuses:)
    uri = build_uri(path, query)
    request = build_request(method, uri, payload)
    response = perform_request(uri, request)
    code = response.code.to_i

    unless expected_statuses.include?(code)
      raise "SendFox API #{method.to_s.upcase} #{uri} failed (#{response.code}): #{response.body}"
    end

    return {} if response.body.to_s.strip.empty?

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise "Invalid JSON from SendFox API #{method.to_s.upcase} #{uri}: #{e.message}"
  end

  def build_uri(path, query)
    uri = URI.join(API_BASE_URL, path)
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

    request["Authorization"] = "Bearer #{@token}"
    request["Content-Type"] = "application/json" if payload
    request.body = JSON.dump(payload) if payload
    request
  end

  def perform_request(uri, request)
    Net::HTTP.start(
      uri.hostname,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: 10,
      read_timeout: 30
    ) do |http|
      http.request(request)
    end
  end

  def truncate(text, max_length)
    return text if text.length <= max_length

    text.each_char.take(max_length).join
  end

  def parse_positive_int(value, default:)
    parsed = Integer(value, exception: false)
    return default unless parsed && parsed.positive?

    parsed
  end

  def truthy?(value)
    %w[1 true yes on].include?(value.to_s.strip.downcase)
  end
end

SendfoxDraftCampaignCreator.new.run
