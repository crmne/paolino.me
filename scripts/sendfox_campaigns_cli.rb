#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"

require "jekyll"
require_relative "../_plugins/sendfox_campaigns"

module SendfoxCampaignsCLI
  module_function

  DEFAULT_DESTINATION = "_site_sendfox_cli"
  COMMANDS = %w[preview publish].freeze

  def run(argv)
    command = extract_command!(argv)
    options = parse_options!(argv)
    site = build_site(options)
    configure_sendfox!(site, options)

    publisher = Jekyll::SendfoxCampaigns::Publisher.new(site)

    case command
    when "preview"
      preview(publisher, options)
    when "publish"
      publisher.publish
    end
  end

  def extract_command!(argv)
    return "preview" if argv.empty? || argv.first.start_with?("-")

    command = argv.shift
    return command if COMMANDS.include?(command)

    abort("Unknown command: #{command.inspect}. Expected one of: #{COMMANDS.join(', ')}")
  end

  def parse_options!(argv)
    options = {
      source: ".",
      destination: DEFAULT_DESTINATION,
      config: nil,
      html_out: nil,
      json_out: nil,
      dry_run: nil,
      update_existing_draft: false,
      skip_in_development: false
    }

    parser = OptionParser.new do |opts|
      opts.banner = "Usage: bundle exec ruby scripts/sendfox_campaigns_cli.rb [preview|publish] [options]"

      opts.on("--source PATH", "Jekyll source directory (default: .)") do |value|
        options[:source] = value
      end

      opts.on("--destination PATH", "Jekyll destination dir (default: #{DEFAULT_DESTINATION})") do |value|
        options[:destination] = value
      end

      opts.on("--config PATHS", "Comma-separated Jekyll config files") do |value|
        options[:config] = value
      end

      opts.on("--html-out PATH", "Preview only: write rendered email HTML to file") do |value|
        options[:html_out] = value
      end

      opts.on("--json-out PATH", "Preview only: write preview JSON to file") do |value|
        options[:json_out] = value
      end

      opts.on("--dry-run", "Publish only: force dry run (no SendFox API writes)") do
        options[:dry_run] = true
      end

      opts.on("--no-dry-run", "Publish only: force API writes") do
        options[:dry_run] = false
      end

      opts.on("--update-existing-draft", "Publish only: patch existing draft campaign with same title") do
        options[:update_existing_draft] = true
      end

      opts.on("--skip-in-development", "Respect skip_in_development during publish") do
        options[:skip_in_development] = true
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

  def configure_sendfox!(site, options)
    sendfox_config = site.config["sendfox_campaigns"]
    sendfox_config = sendfox_config.is_a?(Hash) ? sendfox_config.dup : {}

    sendfox_config["enabled"] = true
    sendfox_config["skip_in_development"] = options[:skip_in_development]
    sendfox_config["update_existing_draft"] = true if options[:update_existing_draft]
    sendfox_config["dry_run"] = options[:dry_run] unless options[:dry_run].nil?

    site.config["sendfox_campaigns"] = sendfox_config
  end

  def preview(publisher, options)
    data = publisher.campaign_preview
    unless data
      abort("No published posts found.")
    end

    payload = data.fetch(:payload)
    post = data.fetch(:post)
    output = {
      campaign_title: data.fetch(:campaign_title),
      post_url: data.fetch(:post_url),
      post_path: relative_or_path(post),
      payload: payload
    }

    puts JSON.pretty_generate(output)
    write_file(options[:html_out], payload.fetch(:html))
    write_file(options[:json_out], JSON.pretty_generate(output))
  end

  def write_file(path, content)
    return if path.to_s.strip.empty?

    absolute = File.expand_path(path)
    File.write(absolute, content)
    warn("Wrote #{absolute}")
  end

  def relative_or_path(post)
    return post.relative_path if post.respond_to?(:relative_path) && !post.relative_path.to_s.empty?

    post.path.to_s
  end
end

SendfoxCampaignsCLI.run(ARGV)
