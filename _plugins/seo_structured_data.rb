# frozen_string_literal: true

# Tighten the JSON-LD emitted by jekyll-ai-visible-content around the site's
# real capabilities and Google's recommended author/profile properties.
module PaolinoWebsiteSchema
  def build
    data = super
    data.delete("potentialAction") # The site has an overlay, not a /search endpoint.

    alternate_name = config.site.config["alternate_title"]
    data["alternateName"] = alternate_name if alternate_name
    data["inLanguage"] = config.site.config["lang"] if config.site.config["lang"]
    data
  end
end

module PaolinoPersonSchema
  def to_hash
    data = super
    site_config = config.site.config
    author = site_config["author"] || {}

    data["url"] = "#{config.site_url}/about/"
    if data["image"].is_a?(Hash)
      data["image"]["width"] = author["image_width"] if author["image_width"]
      data["image"]["height"] = author["image_height"] if author["image_height"]
    end
    if data["worksFor"].is_a?(Hash) && author["company_url"]
      data["worksFor"]["url"] = author["company_url"]
    end
    data
  end
end

module PaolinoBlogPostingSchema
  def build
    data = super
    site_config = config.site.config
    author_config = site_config["author"] || {}
    author = {
      "@type" => "Person",
      "@id" => config.entity_id,
      "name" => author_config["name"] || config.entity["name"],
      "url" => "#{config.site_url}/about/"
    }.compact

    data["author"] = author
    data["publisher"] = author
    data["inLanguage"] = site_config["lang"] if site_config["lang"]
    data["image"] = representative_image if representative_image
    data
  end

  private

  def representative_image
    raw = page.data["media_image"] || page.data["social_image"] || page.data["image"]
    path, width, height = image_parts(raw)
    return unless path

    image = {
      "@type" => "ImageObject",
      "url" => absolute_url(path)
    }
    width ||= page.data["media_image_width"]
    height ||= page.data["media_image_height"]
    image["width"] = width if width
    image["height"] = height if height
    image
  end

  def image_parts(raw)
    case raw
    when Hash
      [raw["path"] || raw[:path] || raw["url"] || raw[:url],
       raw["width"] || raw[:width], raw["height"] || raw[:height]]
    when String
      [raw, nil, nil]
    else
      [nil, nil, nil]
    end
  end
end

module PaolinoStructuredDataBuilder
  def build_for_page(page)
    nodes = super
    return nodes if page.data["robots"].to_s.include?("noindex")

    if profile_page?(page)
      nodes << {
        "@type" => "ProfilePage",
        "@id" => "#{absolute_page_url(page)}#profile",
        "url" => absolute_page_url(page),
        "name" => page.data["seo_title"] || page.data["title"],
        "description" => page.data["description"],
        "mainEntity" => registry.primary_entity_ref,
        "isPartOf" => { "@id" => "#{config.site_url}/#website" },
        "inLanguage" => config.site.config["lang"]
      }.compact
    elsif !post_document?(page)
      nodes << {
        "@type" => page.data["layout"] == "tag_page" ? "CollectionPage" : "WebPage",
        "@id" => "#{absolute_page_url(page)}#webpage",
        "url" => absolute_page_url(page),
        "name" => page.data["seo_title"] || page.data["title"] || config.site_title,
        "description" => page.data["description"] || config.site_description,
        "isPartOf" => { "@id" => "#{config.site_url}/#website" },
        "inLanguage" => config.site.config["lang"]
      }.compact
    end

    nodes
  end

  private

  def profile_page?(page)
    page.data["entity_type"] == "Person" || page.url.to_s.match?(%r{/about/?$})
  end

  def post_document?(page)
    page.respond_to?(:collection) && page.collection&.label == "posts"
  end

  def absolute_page_url(page)
    "#{config.site_url}#{page.url}".sub(%r{index\.html\z}, "")
  end
end

JekyllAiVisibleContent::JsonLd::WebsiteSchema.prepend(PaolinoWebsiteSchema)
JekyllAiVisibleContent::Entity::Person.prepend(PaolinoPersonSchema)
JekyllAiVisibleContent::JsonLd::BlogPostingSchema.prepend(PaolinoBlogPostingSchema)
JekyllAiVisibleContent::JsonLd::Builder.prepend(PaolinoStructuredDataBuilder)
