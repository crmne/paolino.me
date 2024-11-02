module Jekyll
  class TagPageGenerator < Generator
    safe true

    def generate(site)
      if site.layouts.key? 'tag_page'
        dir = site.config['tag_page_dir'] || 'tag'
        site.tags.keys.each do |tag|
          write_tag_page(site, dir, tag)
        end
      end
    end

    def write_tag_page(site, dir, tag)
      # Use Jekyll's built-in slugify filter for consistency
      tag_slug = Jekyll::Utils.slugify(tag.to_s, :mode => 'pretty')

      page = TagPage.new(site, site.source, File.join(dir, tag_slug), tag)
      page.render(site.layouts, site.site_payload)
      page.write(site.dest)
      site.pages << page
    end
  end

  class TagPage < Page
    def initialize(site, base, dir, tag)
      @site = site
      @base = base
      @dir = dir
      @name = 'index.html'

      self.process(@name)
      self.read_yaml(File.join(base, '_layouts'), 'tag_page.html')
      self.data['tag'] = tag
      self.data['title'] = "Posts tagged with #{tag}"
      # Filter posts to only include those with this specific tag
      self.data['posts'] = site.posts.docs.select { |post| post.data['tags'].include?(tag) if post.data['tags'] }
    end
  end
end
