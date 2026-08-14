#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "json"
require "set"
require "uri"

site_dir = File.expand_path(ARGV.fetch(0, "_site"), Dir.pwd)
abort "Build directory not found: #{site_dir}" unless Dir.exist?(site_dir)

errors = []
warnings = []
indexable_pages = []
canonical_to_file = {}
title_to_file = {}
description_to_file = {}
local_references = []

def attributes(tag)
  tag.scan(/([:\w-]+)\s*=\s*(["'])(.*?)\2/m).to_h { |name, _quote, value| [name.downcase, CGI.unescapeHTML(value)] }
end

def tags(html, name)
  html.scan(/<#{Regexp.escape(name)}\b[^>]*>/im)
end

def element_text(html, name)
  html[/<#{Regexp.escape(name)}\b[^>]*>(.*?)<\/#{Regexp.escape(name)}>/im, 1]&.gsub(/<[^>]+>/, "")&.then { |s| CGI.unescapeHTML(s).strip }
end

def meta_content(head, key, value)
  tags(head, "meta").filter_map { |tag| attributes(tag) }.find { |attrs| attrs[key] == value }&.fetch("content", nil)
end

def link_href(head, rel)
  tags(head, "link").filter_map { |tag| attributes(tag) }.find { |attrs| attrs["rel"].to_s.split.include?(rel) }&.fetch("href", nil)
end

def json_ld_nodes(html, file, errors)
  scripts = html.scan(%r{<script\b[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>}im).flatten
  scripts.flat_map do |source|
    parsed = JSON.parse(source)
    parsed.fetch("@graph", [parsed])
  rescue JSON::ParserError => e
    errors << "#{file}: invalid JSON-LD (#{e.message})"
    []
  end
end

html_files = Dir[File.join(site_dir, "**", "*.html")].reject { |file| file.include?("/ai/") }.sort

html_files.each do |file|
  relative = file.delete_prefix("#{site_dir}/")
  html = File.read(file)
  head = html[%r{<head\b[^>]*>(.*?)</head>}im, 1]
  unless head
    errors << "#{relative}: missing <head>"
    next
  end

  title = element_text(head, "title")
  description = meta_content(head, "name", "description")
  robots = meta_content(head, "name", "robots").to_s.downcase
  canonical = link_href(head, "canonical")
  noindex = robots.split(",").map(&:strip).include?("noindex")

  errors << "#{relative}: missing title" if title.to_s.empty?
  errors << "#{relative}: missing meta description" if description.to_s.empty?
  errors << "#{relative}: missing canonical" if canonical.to_s.empty?
  errors << "#{relative}: canonical must be absolute HTTPS (#{canonical})" unless canonical.to_s.start_with?("https://paolino.me/")
  errors << "#{relative}: missing robots directives" if robots.empty?
  errors << "#{relative}: missing html lang" unless html.match?(/<html\b[^>]*lang=["']en-US["']/i)
  errors << "#{relative}: expected exactly one h1" unless html.scan(/<h1\b/i).size == 1
  warnings << "#{relative}: title is #{title.length} characters" if title && title.length > 65
  warnings << "#{relative}: description is #{description.length} characters" if description && !noindex && !(50..170).cover?(description.length)

  %w[og:title og:description og:url og:image og:image:alt].each do |property|
    errors << "#{relative}: missing #{property}" if meta_content(head, "property", property).to_s.empty?
  end
  %w[twitter:card twitter:title twitter:description twitter:image twitter:image:alt].each do |name|
    errors << "#{relative}: missing #{name}" if meta_content(head, "name", name).to_s.empty?
  end

  tags(html, "img").each_with_index do |tag, index|
    attrs = attributes(tag)
    errors << "#{relative}: image #{index + 1} missing alt attribute" unless attrs.key?("alt")
    errors << "#{relative}: image #{index + 1} missing intrinsic width/height" unless attrs["width"] && attrs["height"]
  end

  page_url = relative == "index.html" ? "/" : "/#{relative.sub(%r{index\.html\z}, '')}"
  html.scan(/<(?:a|link)\b[^>]*\bhref\s*=\s*(["'])(.*?)\1/im).each do |_quote, href|
    local_references << [relative, page_url, CGI.unescapeHTML(href)]
  end
  html.scan(/<(?:img|script|source|iframe)\b[^>]*\bsrc\s*=\s*(["'])(.*?)\1/im).each do |_quote, src|
    local_references << [relative, page_url, CGI.unescapeHTML(src)]
  end
  html.scan(/\bsrcset\s*=\s*(["'])(.*?)\1/im).each do |_quote, srcset|
    srcset.split(",").each do |candidate|
      local_references << [relative, page_url, CGI.unescapeHTML(candidate.strip.split(/\s+/, 2).first)]
    end
  end

  nodes = json_ld_nodes(html, relative, errors)
  if nodes.any? { |node| node["@type"] == "BlogPosting" }
    article = nodes.find { |node| node["@type"] == "BlogPosting" }
    %w[headline description datePublished dateModified image author].each do |key|
      errors << "#{relative}: BlogPosting missing #{key}" if article[key].nil? || article[key] == ""
    end
    errors << "#{relative}: BlogPosting author missing name" if article.dig("author", "name").to_s.empty?
    errors << "#{relative}: BlogPosting author missing profile URL" if article.dig("author", "url").to_s.empty?
  end

  next if noindex

  indexable_pages << [relative, canonical]
  if title_to_file.key?(title)
    errors << "#{relative}: duplicate title with #{title_to_file[title]} (#{title})"
  else
    title_to_file[title] = relative
  end
  if description_to_file.key?(description)
    errors << "#{relative}: duplicate description with #{description_to_file[description]}"
  else
    description_to_file[description] = relative
  end
  if canonical_to_file.key?(canonical)
    errors << "#{relative}: duplicate canonical with #{canonical_to_file[canonical]} (#{canonical})"
  else
    canonical_to_file[canonical] = relative
  end
end

local_references.uniq.each do |relative, page_url, reference|
  next if reference.to_s.empty? || reference.include?("{") || reference.start_with?("#", "mailto:", "tel:", "data:", "javascript:")

  uri = URI.join("https://paolino.me#{page_url}", reference)
  next unless [nil, "paolino.me", "www.paolino.me"].include?(uri.host)

  path = URI::DEFAULT_PARSER.unescape(uri.path)
  candidates = if path.end_with?("/")
                 [File.join(site_dir, path.sub(%r{\A/}, ""), "index.html")]
               else
                 absolute = File.join(site_dir, path.sub(%r{\A/}, ""))
                 [absolute, File.join(absolute, "index.html")]
               end
  errors << "#{relative}: broken local reference #{reference}" unless candidates.any? { |candidate| File.file?(candidate) }
rescue URI::InvalidURIError
  errors << "#{relative}: invalid URL reference #{reference}"
end

homepage = File.read(File.join(site_dir, "index.html"))
homepage_nodes = json_ld_nodes(homepage, "index.html", errors)
website = homepage_nodes.find { |node| node["@type"] == "WebSite" }
errors << "index.html: missing WebSite structured data" unless website
errors << "index.html: WebSite missing alternateName" if website && website["alternateName"].to_s.empty?
errors << "index.html: advertises a nonexistent search action" if website&.key?("potentialAction")

about_nodes = json_ld_nodes(File.read(File.join(site_dir, "about", "index.html")), "about/index.html", errors)
profile = about_nodes.find { |node| node["@type"] == "ProfilePage" }
errors << "about/index.html: missing ProfilePage structured data" unless profile&.dig("mainEntity", "@id")

sitemap_path = File.join(site_dir, "sitemap.xml")
if File.file?(sitemap_path)
  sitemap_urls = File.read(sitemap_path).scan(%r{<loc>(.*?)</loc>}).flatten.map { |url| CGI.unescapeHTML(url) }
  errors << "sitemap.xml: duplicate URLs" unless sitemap_urls.uniq.size == sitemap_urls.size
  indexable_pages.each do |relative, canonical|
    next if relative == "404.html"
    next if canonical.include?("/thank-you/")

    errors << "#{relative}: indexable canonical absent from sitemap" unless sitemap_urls.include?(canonical)
  end

  noindex_canonicals = html_files.filter_map do |file|
    html = File.read(file)
    head = html[%r{<head\b[^>]*>(.*?)</head>}im, 1].to_s
    robots = meta_content(head, "name", "robots").to_s
    link_href(head, "canonical") if robots.downcase.split(",").map(&:strip).include?("noindex")
  end.to_set
  overlap = sitemap_urls.to_set & noindex_canonicals
  errors << "sitemap.xml: contains noindex URLs: #{overlap.to_a.join(', ')}" if overlap.any?
else
  errors << "missing sitemap.xml"
end

robots_path = File.join(site_dir, "robots.txt")
errors << "robots.txt: missing sitemap declaration" unless File.file?(robots_path) && File.read(robots_path).include?("Sitemap: https://paolino.me/sitemap.xml")

if warnings.any?
  puts "SEO audit warnings (#{warnings.size}):"
  warnings.each { |warning| puts "  - #{warning}" }
end

if errors.any?
  warn "SEO audit failed (#{errors.size} errors):"
  errors.each { |error| warn "  - #{error}" }
  exit 1
end

puts "SEO audit passed: #{html_files.size} HTML pages, #{indexable_pages.size} indexable pages, valid metadata, JSON-LD, images, local links, sitemap, and robots.txt."
