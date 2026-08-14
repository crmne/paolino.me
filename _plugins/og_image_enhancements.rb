# frozen_string_literal: true

require "jekyll_og_image"
require "fileutils"

class OgImageEnhancements < Jekyll::Generator
  safe true
  priority :highest

  RESPONSIVE_WIDTHS = [160, 480, 800, 1200].freeze
  RESPONSIVE_OUTPUT_DIR = "assets/images/responsive"

  def generate(site)
    og_config = site.config["og_image"] || {}
    collections = og_config["collections"] || [ "posts" ]
    output_dir = og_config["output_dir"] || "assets/images/og"
    canvas_config = og_config["canvas"] || {}

    collections.each do |type|
      items_for(site, type).each do |item|
        # Preserve author-provided media before jekyll-og-image reuses "image"
        # for generated social preview metadata.
        item.data["media_image"] ||= media_image_path(item.data["image"])
        add_image_dimensions(site, item.data, "media_image")
        add_responsive_images(site, item.data, item_slug(item))

        merged_config = Jekyll::Utils.deep_merge_hashes(og_config, item.data["og_image"] || {})
        next unless og_image_enabled?(merged_config)

        item.data["social_image"] ||= {
          "path" => generated_image_path(item, type, output_dir),
          "width" => canvas_config["width"] || 1200,
          "height" => canvas_config["height"] || 600,
          "alt" => item.data["title"] || site.config["title"]
        }

        next if background_image_configured?(merged_config)

        background_image = local_image_path(item.data["image"])
        next unless background_image

        item.data["og_image"] ||= {}
        item.data["og_image"]["canvas"] ||= {}
        item.data["og_image"]["canvas"]["background_image"] = background_image
        item.data["og_image"]["header"] ||= {}
        item.data["og_image"]["header"]["color"] ||= "#FFFFFF"
        item.data["og_image"]["content"] ||= {}
        item.data["og_image"]["content"]["color"] ||= "#FFFFFF"
      end
    end

    # Pages are not part of the OG-image collection, but their visible hero
    # images still need intrinsic dimensions to prevent layout shifts.
    site.pages.each do |page|
      page.data["media_image"] ||= media_image_path(page.data["image"])
      add_image_dimensions(site, page.data, "media_image")
      add_responsive_images(site, page.data, item_slug(page))
    end


    author = site.config["author"] || {}
    if author["avatar"]
      generated = responsive_images_for(site, author["avatar"], "carmine-paolino-avatar", [160])
      author["avatar_responsive"] = generated.first&.fetch("path", nil)
    end
  end

  private

  def items_for(site, type)
    case type
    when "posts"
      site.posts.docs
    when "pages"
      site.pages.select(&:html?)
    else
      site.collections.key?(type) ? site.collections[type].docs : []
    end
  end

  def og_image_enabled?(config)
    config["enabled"].nil? ? true : config["enabled"]
  end

  def background_image_configured?(config)
    canvas = config["canvas"]
    return false unless canvas.is_a?(Hash)

    value = canvas["background_image"] || canvas[:background_image]
    value && !value.to_s.strip.empty?
  end

  def local_image_path(image)
    path =
      case image
      when Hash
        image["path"] || image[:path]
      when String
        image
      end

    return if path.nil?

    path = path.to_s.strip
    return if path.empty?
    return if path.match?(%r{\A[a-z]+://}i)
    return if path.start_with?("data:")

    path
  end

  def media_image_path(image)
    path =
      case image
      when Hash
        image["path"] || image[:path] || image["url"] || image[:url]
      when String
        image
      end

    return if path.nil?

    path = path.to_s.strip
    return if path.empty?

    path
  end

  def generated_image_path(item, type, output_dir)
    fallback_basename =
      if item.respond_to?(:basename_without_ext)
        item.basename_without_ext
      else
        File.basename(item.name, File.extname(item.name))
      end

    slug = item.data["slug"] || Jekyll::Utils.slugify(item.data["title"] || fallback_basename)

    File.join("/", output_dir, type, "#{slug}.png")
  end

  def item_slug(item)
    fallback = if item.respond_to?(:basename_without_ext)
                 item.basename_without_ext
               elsif item.respond_to?(:name)
                 File.basename(item.name, File.extname(item.name))
               else
                 "image"
               end

    item.data["slug"] || Jekyll::Utils.slugify(item.data["title"] || fallback)
  end

  def add_image_dimensions(site, data, key)
    path = data[key]
    return unless path
    return if path.match?(%r{\A[a-z]+://}i)

    absolute_path = File.join(site.source, path.sub(%r{\A/}, ""))
    return unless File.file?(absolute_path)

    width, height = image_dimensions(absolute_path)
    data["#{key}_width"] ||= width
    data["#{key}_height"] ||= height
  rescue Vips::Error => e
    Jekyll.logger.warn "Image metadata:", "Could not inspect #{path}: #{e.message}"
  end

  def image_dimensions(path)
    if File.extname(path).downcase == ".svg"
      header = File.read(path, 1024)
      width = header[/\bwidth=["']([0-9.]+)["']/, 1]&.to_f&.round
      height = header[/\bheight=["']([0-9.]+)["']/, 1]&.to_f&.round
      return [width, height] if width && height
    end

    image = Vips::Image.new_from_file(path, access: :sequential)
    [image.width, image.height]
  end

  def add_responsive_images(site, data, slug)
    path = data["media_image"]
    return unless path

    generated = responsive_images_for(site, path, slug, RESPONSIVE_WIDTHS)
    return if generated.empty?

    avif_generated = responsive_images_for(site, path, slug, RESPONSIVE_WIDTHS, format: "avif")

    data["responsive_images"] = generated
    data["responsive_avif_images"] = avif_generated unless avif_generated.empty?
    data["responsive_image_thumbnail"] = generated.min_by { |entry| (entry["width"] - 160).abs }["path"]
    data["responsive_image_src"] = generated.min_by { |entry| (entry["width"] - 800).abs }["path"]
    data["media_image_animated"] = File.extname(path).downcase == ".gif"
  end

  def responsive_images_for(site, path, slug, widths, format: "webp")
    return [] if path.match?(%r{\A[a-z]+://}i)
    return [] if File.extname(path).downcase == ".svg"

    absolute_path = File.join(site.source, path.sub(%r{\A/}, ""))
    return [] unless File.file?(absolute_path)

    source = Vips::Image.new_from_file(absolute_path, access: :sequential)
    widths.filter_map do |requested_width|
      target_width = [requested_width, source.width].min
      filename = "#{slug}-#{target_width}.#{format}"
      output_path = File.join(site.source, RESPONSIVE_OUTPUT_DIR, filename)
      FileUtils.mkdir_p(File.dirname(output_path))

      unless File.file?(output_path) && File.mtime(output_path) >= File.mtime(absolute_path)
        image = Vips::Image.thumbnail(absolute_path, target_width, size: :down, auto_rotate: true)
        if format == "avif"
          image.heifsave(output_path, Q: 55, strip: true, effort: 4, compression: :av1)
        else
          image.webpsave(output_path, Q: 82, strip: true, effort: 4)
        end
      end

      register_static_file(site, filename)
      generated = Vips::Image.new_from_file(output_path, access: :sequential)
      {
        "path" => File.join("/", RESPONSIVE_OUTPUT_DIR, filename),
        "width" => generated.width,
        "height" => generated.height
      }
    end.uniq { |entry| entry["width"] }
  rescue Vips::Error => e
    Jekyll.logger.warn "Responsive images:", "Could not optimize #{path}: #{e.message}"
    []
  end

  def register_static_file(site, filename)
    path = File.join("/", RESPONSIVE_OUTPUT_DIR, filename)
    return if site.static_files.any? { |file| file.relative_path == path }

    site.static_files << Jekyll::StaticFile.new(site, site.source, RESPONSIVE_OUTPUT_DIR, filename)
  end
end

class JekyllOgImage::Element::Canvas
  def initialize(width, height, background_color: "#ffffff", background_image: nil)
    @canvas = Vips::Image.black(width, height).ifthenelse([ 0, 0, 0 ], hex_to_rgb(background_color))

    return @canvas unless background_image

    overlay = Vips::Image.new_from_buffer(background_image, "")
    overlay = overlay.flatten if overlay.has_alpha?

    ratio = calculate_ratio(overlay, width, height, :max)
    overlay = overlay.resize(ratio)

    x = [ (overlay.width - width) / 2, 0 ].max
    y = [ (overlay.height - height) / 2, 0 ].max
    overlay = overlay.crop(x, y, width, height)
    overlay = overlay.gaussblur(1.5).linear(0.5, 0)

    @canvas = overlay.copy(interpretation: :srgb)
  end
end
