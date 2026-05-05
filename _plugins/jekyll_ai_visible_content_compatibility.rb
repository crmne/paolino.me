# frozen_string_literal: true

begin
  require "jekyll-ai-visible-content"
rescue LoadError => e
  Jekyll.logger.warn("AI Visible Content compatibility:", e.message)
end

if defined?(JekyllAiVisibleContent::Configuration)
  class JekyllAiVisibleContent::Configuration
    def seo_tag_present?
      Array(site.config["plugins"]).include?("jekyll-seo-tag")
    end
  end
end

if defined?(JekyllAiVisibleContent::JsonLd::BlogPostingSchema)
  class JekyllAiVisibleContent::JsonLd::BlogPostingSchema
    private

    def append_image(posting, data)
      image = data["image"]
      image = image["path"] || image[:path] if image.is_a?(Hash)

      return if image.to_s.strip.empty?

      posting["image"] = absolute_url(image.to_s)
    end
  end
end

if defined?(JekyllAiVisibleContent::JsonLd::WebsiteSchema)
  class JekyllAiVisibleContent::JsonLd::WebsiteSchema
    private

    def append_search_action(_data)
      nil
    end
  end
end

if defined?(JekyllAiVisibleContent::Validators::EntityConsistencyValidator)
  class JekyllAiVisibleContent::Validators::EntityConsistencyValidator
    private

    def check_generic_titles
      warnings = []
      generic = %w[about blog home page post]

      content_docs.each do |doc|
        next if doc.data["seo_title"].to_s.strip != ""

        title = doc.data["title"].to_s.strip.downcase
        next unless generic.include?(title)

        path = doc.respond_to?(:relative_path) ? doc.relative_path : doc.url
        warnings << "Generic title '#{doc.data["title"]}' in #{path} (include entity name for discoverability)"
      end

      warnings
    end
  end
end

if defined?(JekyllAiVisibleContent::Hooks::PostRenderHook)
  class << JekyllAiVisibleContent::Hooks::PostRenderHook
    unless private_method_defined?(:inject_ai_resource_links_without_content_filter)
      alias_method :inject_ai_resource_links_without_content_filter, :inject_ai_resource_links
    end

    private

    def inject_ai_resource_links(doc, config)
      return unless JekyllAiVisibleContent::ContentFilter.content_page?(doc, config)

      inject_ai_resource_links_without_content_filter(doc, config)
    end
  end
end
