# frozen_string_literal: true

Jekyll::Hooks.register :documents, :pre_render do |doc|
  next unless doc.collection&.label == "posts"

  doc.data["last_modified_at"] ||= doc.data["date"]
  doc.data["topics"] ||= doc.data["tags"] if doc.data["tags"]
end

Jekyll::Hooks.register :pages, :pre_render do |page|
  next unless page.url.to_s.start_with?("/tag/")

  tag = page.data["tag"] || page.url.to_s.split("/").reject(&:empty?).last
  tag_name = tag.to_s.split("-").map(&:capitalize).join(" ")

  page.data["title"] ||= "Posts tagged with #{tag_name}"
  page.data["description"] ||= "Posts about #{tag_name} by #{page.site.config["title"]}."
  page.data["nav"] = false
end
