# frozen_string_literal: true

require "json"

# Structured data and AI discovery files for the site: JSON-LD in every page
# head ({% json_ld %}), related posts ({% related_posts %}), llms.txt,
# llms-full.txt and robots.txt. Configured under `structured_data:` in
# _config.yml.
module PaolinoStructuredData
  module_function

  def config(site)
    site.config["structured_data"] || {}
  end

  def entity(site)
    config(site)["entity"] || {}
  end

  def site_url(site)
    site.config["url"].to_s.sub(%r{/+\z}, "")
  end

  def absolute_url(site, path)
    return if path.to_s.empty?
    return path if path.to_s.start_with?("http")

    "#{site_url(site)}#{path}"
  end

  def page_url(site, page)
    absolute_url(site, page["url"].to_s.sub(/index\.html\z/, ""))
  end

  def person_id(site)
    "#{site_url(site)}/##{entity(site)['id_slug']}"
  end

  def person_ref(site)
    { "@type" => "Person", "@id" => person_id(site) }
  end

  def author_ref(site)
    {
      "@type" => "Person",
      "@id" => person_id(site),
      "name" => site.config.dig("author", "name") || entity(site)["name"],
      "url" => "#{site_url(site)}/about/"
    }.compact
  end

  def website_ref(site)
    { "@id" => "#{site_url(site)}/#website" }
  end

  def lang(site)
    site.config["lang"]
  end

  def clean(text)
    value = text.to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
    value.empty? ? nil : value
  end

  def person(site)
    data = entity(site)
    author = site.config["author"] || {}
    image = absolute_url(site, data["image"])
    works_for = data["works_for"] || {}
    occupation = data["occupation"] || {}

    {
      "@type" => "Person",
      "@id" => person_id(site),
      "name" => data["name"],
      "url" => "#{site_url(site)}/about/",
      "alternateName" => data["alternate_names"],
      "image" => image && {
        "@type" => "ImageObject",
        "url" => image,
        "width" => author["image_width"],
        "height" => author["image_height"]
      }.compact,
      "jobTitle" => data["job_title"],
      "description" => data["description"],
      "knowsAbout" => data["knows_about"],
      "sameAs" => data["same_as"],
      "worksFor" => works_for.empty? ? nil : {
        "@type" => works_for["type"] || "Organization",
        "name" => works_for["name"],
        "url" => works_for["url"]
      }.compact,
      "hasOccupation" => occupation.empty? ? nil : {
        "@type" => "Occupation",
        "name" => occupation["name"],
        "skills" => occupation["skills"]
      }.compact
    }.compact
  end

  def website(site)
    {
      "@type" => "WebSite",
      "@id" => "#{site_url(site)}/#website",
      "url" => site_url(site),
      "name" => site.config["title"],
      "description" => clean(site.config["description"]),
      "publisher" => person_ref(site),
      "alternateName" => site.config["alternate_title"],
      "inLanguage" => lang(site)
    }.compact
  end

  def blog_posting(site, page, content)
    url = page_url(site, page)
    tags = Array(page["tags"])
    topics = Array(page["topics"] || page["categories"])

    {
      "@type" => "BlogPosting",
      "@id" => "#{url}#article",
      "mainEntityOfPage" => { "@type" => "WebPage", "@id" => url },
      "headline" => page["title"],
      "description" => clean(page["description"]),
      "datePublished" => iso8601(page["date"]),
      "dateModified" => iso8601(page["last_modified_at"] || page["date"]),
      "author" => author_ref(site),
      "publisher" => author_ref(site),
      "isPartOf" => website_ref(site),
      "image" => post_image(site, page),
      "keywords" => tags.empty? ? nil : tags,
      "about" => topics.empty? ? nil : topics.map { |topic| { "@type" => "Thing", "name" => topic } },
      "wordCount" => content && clean(content).to_s.split.size,
      "articleBody" => clean(page["description"] || page["excerpt"]),
      "inLanguage" => lang(site)
    }.compact
  end

  def post_image(site, page)
    raw = page["media_image"] || page["social_image"] || page["image"]
    path, width, height =
      if raw.is_a?(Hash)
        [raw["path"] || raw["url"], raw["width"], raw["height"]]
      else
        [raw, nil, nil]
      end
    return if path.to_s.strip.empty?

    {
      "@type" => "ImageObject",
      "url" => absolute_url(site, path),
      "width" => width || page["media_image_width"],
      "height" => height || page["media_image_height"]
    }.compact
  end

  def breadcrumbs(site, page)
    segments = page["url"].to_s.sub(/index\.html\z/, "").split("/").reject(&:empty?)
    return if segments.empty?

    items = [{ "@type" => "ListItem", "position" => 1, "name" => "Home", "item" => "#{site_url(site)}/" }]
    path = ""
    segments.each_with_index do |segment, index|
      path = "#{path}/#{segment}"
      item = { "@type" => "ListItem", "position" => index + 2 }
      if index == segments.size - 1
        item["name"] = page["title"] || humanize(segment)
      else
        item["name"] = humanize(segment)
        item["item"] = "#{site_url(site)}#{path}/"
      end
      items << item
    end

    { "@type" => "BreadcrumbList", "itemListElement" => items }
  end

  def humanize(slug)
    slug.tr("-_", " ").gsub(/\b\w/, &:upcase)
  end

  def profile_page(site, page)
    {
      "@type" => "ProfilePage",
      "@id" => "#{page_url(site, page)}#profile",
      "url" => page_url(site, page),
      "name" => page["seo_title"] || page["title"],
      "description" => page["description"],
      "mainEntity" => person_ref(site),
      "isPartOf" => website_ref(site),
      "inLanguage" => lang(site)
    }.compact
  end

  def web_page(site, page)
    {
      "@type" => page["layout"] == "tag_page" ? "CollectionPage" : "WebPage",
      "@id" => "#{page_url(site, page)}#webpage",
      "url" => page_url(site, page),
      "name" => page["seo_title"] || page["title"] || site.config["title"],
      "description" => page["description"] || clean(site.config["description"]),
      "isPartOf" => website_ref(site),
      "inLanguage" => lang(site)
    }.compact
  end

  def graph(site, page, content)
    url = page["url"].to_s
    return [person(site), website(site)] if ["/", "/index.html"].include?(url)

    post = page["collection"] == "posts"
    profile = page["entity_type"] == "Person" || url.match?(%r{/about/?\z})
    nodes = []
    nodes.push(person(site), website(site)) if profile
    nodes << blog_posting(site, page, content) if post && !profile
    nodes << breadcrumbs(site, page)
    unless page["robots"].to_s.include?("noindex")
      if profile
        nodes << profile_page(site, page)
      elsif !post
        nodes << web_page(site, page)
      end
    end
    nodes.compact
  end

  def iso8601(date)
    return if date.nil?

    date.respond_to?(:iso8601) ? date.iso8601 : date.to_s
  end

  def related_posts(site, current, limit)
    explicit = Array(current.data["related_slugs"]).filter_map do |slug|
      site.posts.docs.find { |post| post.data["slug"] == slug || post.url.include?(slug) }
    end
    return explicit.first(limit) if explicit.any?

    site.posts.docs.reject { |post| post.url == current.url }.filter_map do |post|
      score = (jaccard(current.data["tags"], post.data["tags"]) * 3) +
              (jaccard(current.data["categories"], post.data["categories"]) * 2) +
              jaccard(current.data["topics"], post.data["topics"])
      [post, score] if score.positive?
    end.sort_by { |_, score| -score }.first(limit).map(&:first)
  end

  def jaccard(left, right)
    left = Array(left).map { |value| value.to_s.downcase }
    right = Array(right).map { |value| value.to_s.downcase }
    union = (left | right).size
    union.zero? ? 0.0 : (left & right).size.to_f / union
  end

  class JsonLdTag < Liquid::Tag
    def render(context)
      site = context.registers[:site]
      page = context["page"]
      nodes = PaolinoStructuredData.graph(site, page, context["content"])
      return "" if nodes.empty?

      json = JSON.pretty_generate({ "@context" => "https://schema.org", "@graph" => nodes })
      %(<script type="application/ld+json">\n#{json.gsub("</", "<\\/")}\n</script>)
    end
  end

  class RelatedPostsTag < Liquid::Tag
    def initialize(tag_name, markup, tokens)
      super
      @limit = markup[/limit\s*:\s*(\d+)/, 1]&.to_i || 3
    end

    def render(context)
      site = context.registers[:site]
      current = site.posts.docs.find { |post| post.url == context["page"]["url"] }
      return "" unless current

      posts = PaolinoStructuredData.related_posts(site, current, @limit)
      return "" if posts.empty?

      items = posts.map do |post|
        date = post.data["date"]
        time = date && %(\n      <time itemprop="datePublished" datetime="#{date.strftime('%Y-%m-%d')}">#{date.strftime('%b %d, %Y')}</time>)
        <<~HTML.chomp
          <li itemscope itemtype="https://schema.org/BlogPosting">
                <a itemprop="url" href="#{post.url}">
                  <span itemprop="headline">#{post.data['title']}</span>
                </a>#{time}
              </li>
        HTML
      end

      <<~HTML.chomp
        <nav aria-label="Related posts">
          <h2>Related Posts</h2>
          <ul>
            #{items.join("\n    ")}
          </ul>
        </nav>
      HTML
    end
  end

  class GeneratedFile < Jekyll::PageWithoutAFile
    def initialize(site, name, content)
      super(site, site.source, "", name)
      self.content = content
      data["layout"] = nil
      data["sitemap"] = false
    end

    def render_with_liquid?
      false
    end
  end

  class Generator < Jekyll::Generator
    priority :lowest

    def generate(site)
      settings = PaolinoStructuredData.config(site)
      llms = settings["llms_txt"] || {}
      if llms["enabled"] != false
        posts = site.posts.docs.reject { |post| post.data["published"] == false }.reverse
        site.pages << GeneratedFile.new(site, "llms.txt", llms_index(site, llms, posts))
        site.pages << GeneratedFile.new(site, "llms-full.txt", llms_full(site, llms, posts))
      end
      site.pages << GeneratedFile.new(site, "robots.txt", robots(site, settings["crawlers"] || []))
    end

    private

    def header(site, llms)
      data = PaolinoStructuredData.entity(site)
      lines = ["# #{llms['title'] || site.config['title']}", ""]
      description = PaolinoStructuredData.clean(llms["description"] || site.config["description"])
      lines.push("> #{description}", "") if description
      lines.push("## About", "", "#{data['name']} is #{data['description']}", "")
      lines.push("- Role: #{data['job_title']}", "") if data["job_title"]
      topics = Array(data["knows_about"])
      lines.push("## Key Topics", "", *topics.map { |topic| "- #{topic}" }, "") if topics.any?
      Array(llms["sections"]).each do |section|
        lines.push("## #{section['heading']}", "", section["content"].to_s.strip, "")
      end
      lines
    end

    def llms_index(site, llms, posts)
      lines = header(site, llms)
      lines.push("## Posts", "")
      posts.each do |post|
        entry = "- [#{post.data['title']}](#{PaolinoStructuredData.absolute_url(site, post.url)})"
        description = PaolinoStructuredData.clean(post.data["description"])
        entry += ": #{description}" if description
        lines << entry
      end
      lines.push("", "## Links", "", "- About: #{PaolinoStructuredData.site_url(site)}/about/")
      Array(PaolinoStructuredData.entity(site)["same_as"]).each do |url|
        lines << "- #{link_label(url)}: #{url}"
      end
      "#{lines.join("\n")}\n"
    end

    def llms_full(site, llms, posts)
      lines = header(site, llms)
      posts.each do |post|
        lines.push("---", "", "# #{post.data['title']}", "")
        lines.push("URL: #{PaolinoStructuredData.absolute_url(site, post.url)}")
        lines.push("Published: #{post.data['date'].strftime('%Y-%m-%d')}") if post.data["date"]
        lines.push("", post.content.to_s.strip, "")
      end
      "#{lines.join("\n").rstrip}\n"
    end

    def robots(site, crawlers)
      lines = ["User-agent: *", "Allow: /", ""]
      crawlers.each { |agent| lines.push("User-agent: #{agent}", "Allow: /", "") }
      lines << "Sitemap: #{PaolinoStructuredData.site_url(site)}/sitemap.xml"
      "#{lines.join("\n")}\n"
    end

    def link_label(url)
      host = url.sub(%r{\Ahttps?://(www\.)?}, "").split(/[.\/]/).first.to_s
      { "x" => "Twitter", "github" => "GitHub", "linkedin" => "LinkedIn" }.fetch(host, host.capitalize)
    end
  end
end

Liquid::Template.register_tag("json_ld", PaolinoStructuredData::JsonLdTag)
Liquid::Template.register_tag("related_posts", PaolinoStructuredData::RelatedPostsTag)
