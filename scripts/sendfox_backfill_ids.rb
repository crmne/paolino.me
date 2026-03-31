#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "time"
require "uri"

require "jekyll"
require_relative "../_plugins/sendfox_campaigns"

module SendfoxBackfillIds
  module_function

  DEFAULTS = {
    source: ".",
    destination: "_site_sendfox_backfill",
    config: nil,
    api_base_url: "https://api.sendfox.com",
    max_pages: 100,
    apply: false,
    verbose: false
  }.freeze

  def run(argv)
    options = parse_options(argv)
    token = ENV["SENDFOX_API_TOKEN"].to_s.strip
    abort("Missing SENDFOX_API_TOKEN") if token.empty?

    site = build_site(options)
    previews = campaign_previews_for(site)
    campaigns = fetch_campaigns(
      api_base_url: options[:api_base_url],
      token: token,
      max_pages: options[:max_pages]
    )

    results = plan_backfills(previews, campaigns)
    print_plan(results, campaigns.length)

    return if results[:to_write].empty? || !options[:apply]

    write_count = apply_backfills(results[:to_write], verbose: options[:verbose])
    puts "Applied #{write_count} front-matter updates."
  end

  def parse_options(argv)
    options = DEFAULTS.dup

    parser = OptionParser.new do |opts|
      opts.banner = "Usage: bundle exec ruby scripts/sendfox_backfill_ids.rb [options]"

      opts.on("--source PATH", "Jekyll source directory (default: .)") do |value|
        options[:source] = value
      end

      opts.on("--destination PATH", "Jekyll destination directory") do |value|
        options[:destination] = value
      end

      opts.on("--config PATHS", "Comma-separated Jekyll config files") do |value|
        options[:config] = value
      end

      opts.on("--api-base-url URL", "Sendfox API base URL (default: https://api.sendfox.com)") do |value|
        options[:api_base_url] = value
      end

      opts.on("--max-pages N", Integer, "Max campaign list pages to fetch (default: 100)") do |value|
        options[:max_pages] = value
      end

      opts.on("--apply", "Write sendfox_campaign_id into post front matter") do
        options[:apply] = true
      end

      opts.on("--verbose", "Print each file update") do
        options[:verbose] = true
      end

      opts.on("-h", "--help", "Show this help message") do
        puts opts
        exit 0
      end
    end

    parser.parse!(argv)
    options
  end

  def build_site(options)
    overrides = {
      "source" => options[:source],
      "destination" => options[:destination],
      "sendfox_campaigns" => { "enabled" => false }
    }
    overrides["config"] = options[:config] if options[:config]

    site = Jekyll::Site.new(Jekyll.configuration(overrides))
    site.process
    site
  end

  def campaign_previews_for(site)
    sendfox_config = site.config["sendfox_campaigns"]
    sendfox_config = sendfox_config.is_a?(Hash) ? sendfox_config.dup : {}
    sendfox_config["enabled"] = true
    sendfox_config["post_scope"] = "all"
    sendfox_config["skip_in_development"] = false
    sendfox_config["dry_run"] = true
    site.config["sendfox_campaigns"] = sendfox_config

    publisher = Jekyll::SendfoxCampaigns::Publisher.new(site)
    publisher.campaign_previews
  end

  def fetch_campaigns(api_base_url:, token:, max_pages:)
    campaigns = []
    page = 1

    loop do
      uri = build_uri(api_base_url, "/campaigns", page: page)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"

      response = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 10,
        read_timeout: 30
      ) { |http| http.request(request) }

      status = response.code.to_i
      raise "Sendfox API GET #{uri} failed (#{response.code}): #{response.body}" unless status == 200

      payload = JSON.parse(response.body)
      page_campaigns = Array(payload["data"])
      campaigns.concat(page_campaigns)

      break if page_campaigns.empty?
      break if page >= max_pages

      per_page = payload["per_page"].to_i
      total = payload["total"].to_i
      break if per_page.positive? && total.positive? && (page * per_page) >= total
      break if per_page.positive? && page_campaigns.length < per_page

      page += 1
    end

    campaigns
  end

  def build_uri(base_url, path, query)
    uri = URI.join(base_url, path)
    uri.query = URI.encode_www_form(query) if query && !query.empty?
    uri
  end

  def plan_backfills(previews, campaigns)
    results = {
      total_posts: previews.length,
      already_pinned: [],
      to_write: [],
      missing_campaign: [],
      sent_only: []
    }

    previews.each do |preview|
      post = preview.fetch(:post)
      if preview[:configured_campaign_id]
        results[:already_pinned] << post.relative_path
        next
      end

      matches = campaigns.select { |campaign| campaign_matches_preview?(campaign, preview) }
      draft_matches = matches.select { |campaign| draft_campaign?(campaign) }
      candidate = newest_campaign(draft_matches)

      if candidate
        results[:to_write] << {
          file: post.path.to_s,
          relative_path: post.relative_path.to_s,
          campaign_id: candidate["id"].to_i,
          title: preview.fetch(:campaign_title)
        }
        next
      end

      if matches.empty?
        results[:missing_campaign] << post.relative_path
      else
        results[:sent_only] << {
          post: post.relative_path,
          campaign_ids: matches.map { |c| c["id"] }.compact
        }
      end
    end

    results
  end

  def newest_campaign(campaigns)
    campaigns.max_by do |campaign|
      parse_time(campaign["updated_at"]) || parse_time(campaign["created_at"]) || Time.at(0)
    end
  end

  def parse_time(value)
    return nil if value.to_s.strip.empty?

    Time.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def campaign_matches_preview?(campaign, preview)
    campaign_key = preview.fetch(:campaign_key)
    title = campaign["title"].to_s
    return true if title.include?("[SFPOST:#{campaign_key}]")
    return true if title.end_with?("[#{campaign_key}]")

    source_url = source_post_url_from_html(campaign["html"])
    return false if source_url.to_s.strip.empty?

    normalize_url(source_url) == normalize_url(preview.fetch(:post_url))
  end

  def draft_campaign?(campaign)
    campaign["sent_at"].to_s.strip.empty?
  end

  def source_post_url_from_html(html)
    content = html.to_s

    data_attr_match = content.match(/\bdata-source-post=(['"])(.*?)\1/i)
    return data_attr_match[2] if data_attr_match

    match = content.match(/source-post:\s*([^\s<]+)/i)
    return nil unless match

    match[1]
  end

  def normalize_url(url)
    url.to_s.sub(%r{/$}, "")
  end

  def print_plan(results, campaign_count)
    puts "Posts considered: #{results[:total_posts]}"
    puts "Campaigns fetched: #{campaign_count}"
    puts "Already pinned: #{results[:already_pinned].length}"
    puts "Will backfill: #{results[:to_write].length}"
    puts "Missing campaign: #{results[:missing_campaign].length}"
    puts "Sent-only matches: #{results[:sent_only].length}"

    unless results[:to_write].empty?
      puts "Backfill candidates:"
      results[:to_write].each do |item|
        puts "  - #{item[:relative_path]} -> #{item[:campaign_id]}"
      end
    end

    unless results[:missing_campaign].empty?
      puts "No campaign match:"
      results[:missing_campaign].each { |path| puts "  - #{path}" }
    end

    unless results[:sent_only].empty?
      puts "Only sent campaigns found (not writing ID to avoid pinning to sent):"
      results[:sent_only].each do |item|
        puts "  - #{item[:post]} -> #{item[:campaign_ids].join(', ')}"
      end
    end
  end

  def apply_backfills(items, verbose: false)
    writes = 0

    items.each do |item|
      next unless insert_sendfox_campaign_id(item[:file], item[:campaign_id])

      writes += 1
      puts "Updated #{item[:relative_path]} with sendfox_campaign_id: #{item[:campaign_id]}" if verbose
    end

    writes
  end

  def insert_sendfox_campaign_id(path, campaign_id)
    content = File.read(path)
    match = content.match(/\A---\s*\n(.*?)\n---\s*\n/m)
    return false unless match

    front_matter = match[1]
    return false if front_matter.match?(/^\s*sendfox_campaign_id:/m)

    front_matter = front_matter.sub(/\s*\z/, "")
    replacement = +"---\n"
    replacement << front_matter
    replacement << "\nsendfox_campaign_id: #{campaign_id}\n"
    replacement << "---\n"

    updated = content.sub(/\A---\s*\n(.*?)\n---\s*\n/m, replacement)
    File.write(path, updated)
    true
  end
end

SendfoxBackfillIds.run(ARGV)
