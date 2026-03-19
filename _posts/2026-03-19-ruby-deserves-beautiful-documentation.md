---
layout: post
title: "Ruby Deserves Beautiful Documentation"
date: 2026-03-19
description: "The Ruby community doesn't have a great documentation theme. So I made one. Jekyll VitePress Theme brings VitePress's docs UX to Jekyll."
tags: [Ruby, Jekyll, Documentation, Open Source, VitePress]
image: /images/jekyll-vitepress.png
sendfox_campaign_id: 2751500
---
Have you ever looked at a VitePress documentation site and felt a little jealous?

The sidebar navigation. The "On this page" outline on the right. The search that pops up with `/`. The homepage that actually looks like a product page, not a README with a nav bar. Dark mode that just works. Code blocks with copy buttons and language labels. It all looks like someone sat down and designed the whole experience.

Because someone did. VitePress is genuinely great. And Ruby developers know it, because some of the most visible projects in our community are shipping their docs on VitePress. Not on a Jekyll theme, not on a Ruby tool. On a JavaScript static site generator built for Vue.

I don't blame them. I looked at what we had in the Jekyll ecosystem and understood immediately. The best option is Just the Docs, and I've been using it for [RubyLLM](https://rubyllm.com). It's solid. But I had to patch in proper dark mode support that follows the browser setting. I had to add a copy-page button. The homepage layout is narrow and document-y. It works. It doesn't wow.

So I built [Jekyll VitePress Theme](https://jekyll-vitepress.dev).

## What It Is

A Jekyll theme gem that recreates the VitePress documentation experience. Everything you'd expect:

- Top nav with mobile menu
- Left sidebar, right "On this page" outline
- Homepage layout with hero section and feature cards
- Built-in local search (press `/` or `Cmd+K`)
- Dark/light/auto appearance toggle
- Code blocks with copy buttons, language labels, and file title bars
- Doc footer with edit link, previous/next pager, and "last updated"
- GitHub star widget
- Rouge syntax highlighting with separate light and dark themes

All configured through `_config.yml` and `_data/*.yml` files. No JavaScript toolchain. No Node.js. Just Jekyll.

## Getting Started

```ruby
gem "jekyll-vitepress-theme"
```
{: data-title="Gemfile"}

```yaml
theme: jekyll-vitepress-theme
plugins:
  - jekyll-vitepress-theme

jekyll_vitepress:
  branding:
    site_title: My Project
```
{: data-title="_config.yml"}

```sh
bundle install
bundle exec jekyll serve --livereload
```

That's it. Your docs site now looks like VitePress. Customize the nav, sidebar, colors, fonts, and everything else from the [configuration reference](https://jekyll-vitepress.dev/configuration-reference/).

## Why This Matters

When I came back to Ruby in 2024, I kept finding things that could be better. There wasn't a great LLM library, so I built [RubyLLM](https://rubyllm.com). Async deserved more attention, so I [blogged about it](/async-ruby-is-the-future). And our documentation sites? They didn't look the part.

In open source, looks matter. A beautiful docs site tells potential users: this project is serious, maintained, and worth your time. It lowers the barrier to adoption. It makes people want to try your library.

VitePress understood this. Now Jekyll has it too.

```ruby
gem "jekyll-vitepress-theme", "~> 1.0"
```
