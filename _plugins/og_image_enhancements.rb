# frozen_string_literal: true

require "jekyll_og_image"

class OgImageEnhancements < Jekyll::Generator
  safe true
  priority :highest

  def generate(site)
    og_config = site.config["og_image"] || {}
    collections = og_config["collections"] || [ "posts" ]
    output_dir = og_config["output_dir"] || "assets/images/og"
    canvas_config = og_config["canvas"] || {}

    collections.each do |type|
      items_for(site, type).each do |item|
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
