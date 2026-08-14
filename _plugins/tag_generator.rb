module Jekyll
  class SeoTagPageGenerator < Generator
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

      page = SeoTagPage.new(site, site.source, File.join(dir, tag_slug), tag)
      site.pages << page
    end
  end

  class SeoTagPage < Page
    def initialize(site, base, dir, tag)
      @site = site
      @base = base
      @dir = dir
      @name = 'index.html'

      self.process(@name)
      self.read_yaml(File.join(base, '_layouts'), 'tag_page.html')
      self.data['tag'] = tag
      # Filter posts to only include those with this specific tag
      self.data['posts'] = site.posts.docs.select { |post| post.data['tags'].include?(tag) if post.data['tags'] }
      post_count = self.data['posts'].size

      self.data['title'] = "#{tag} Articles by #{site.config['title']}"
      self.data['description'] = "Explore #{post_count} #{post_count == 1 ? 'article' : 'articles'} about #{tag}, written by #{site.config['title']}."
      self.data['nav'] = false
      self.data['og_type'] = 'website'

      # A one-post archive duplicates the only article without adding useful
      # search value. Keep it crawlable for readers, but out of the index and
      # sitemap until the topic has enough depth to become a real collection.
      if post_count < 2
        self.data['robots'] = 'noindex,follow,max-image-preview:large'
        self.data['sitemap'] = false
      end
    end
  end
end
