# frozen_string_literal: true

module Jekyll
  module FeedSanitizer
    def sanitize_feed_html(html)
      return "" if html.nil?

      content = html.dup

      content.gsub!(
        %r{<div class="language-([A-Za-z0-9_+\-]+)\s+highlighter-rouge">\s*<div class="highlight">\s*<pre class="highlight">\s*<code>(.*?)</code>\s*</pre>\s*</div>\s*</div>}m
      ) do
        language = Regexp.last_match(1)
        code = clean_code_markup(Regexp.last_match(2))
        %(<pre><code class="language-#{language}">#{code}</code></pre>)
      end

      content.gsub!(
        %r{<div class="highlighter-rouge">\s*<div class="highlight">\s*<pre class="highlight">\s*<code>(.*?)</code>\s*</pre>\s*</div>\s*</div>}m
      ) do
        code = clean_code_markup(Regexp.last_match(1))
        %(<pre><code>#{code}</code></pre>)
      end

      content.gsub!(%r{<pre class="highlight">\s*<code>(.*?)</code>\s*</pre>}m) do
        code = clean_code_markup(Regexp.last_match(1))
        %(<pre><code>#{code}</code></pre>)
      end

      # Inline code should not carry Rouge class noise in email feeds.
      content.gsub!(%r{<code class="[^"]*highlighter-rouge[^"]*">}, "<code>")

      content
    rescue StandardError => e
      Jekyll.logger.warn("Feed sanitizer:", "Failed to sanitize post HTML: #{e.message}")
      html
    end

    private

    def clean_code_markup(fragment)
      fragment
        .gsub(%r{<span[^>]*>}, "")
        .gsub(%r{</span>}, "")
    end
  end
end

Liquid::Template.register_filter(Jekyll::FeedSanitizer)

# Jekyll Feed hardcodes its own template, so patch it to use the sanitizer.
begin
  require "jekyll-feed/generator"
rescue LoadError
  # Ignore when jekyll-feed is not installed/enabled.
end

if defined?(JekyllFeed::Generator)
  JekyllFeed::Generator.class_eval do
    alias_method :feed_template_without_feed_sanitizer, :feed_template unless method_defined?(:feed_template_without_feed_sanitizer)

    def feed_template
      @feed_template_with_sanitized_content ||= begin
        template = feed_template_without_feed_sanitizer
        template.gsub("{{ post.content | strip }}", "{{ post.content | sanitize_feed_html | strip }}")
      end
    end
  end
end
