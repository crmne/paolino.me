---
layout: post
title: "Turbo Frames in Jekyll"
date: 2026-05-19
description: "Turbo can make a static Jekyll site feel like an app, but the trick is not the script tag. It's the frame boundary."
tags: [Ruby, Jekyll, Turbo, Hotwire, Documentation]
image: /images/jekyll-vitepress.png
---
I almost made a gem.

While building [Jekyll VitePress Theme](https://jekyll-vitepress.dev), the part that surprised me most was not the CSS. It was navigation.

VitePress feels fast because the shell stays put. The top nav, sidebar, outline, theme switcher, search modal, and scroll position do not get torn down every time you click a page. The content changes, the URL changes, the title changes, and the rest of the interface keeps breathing.

Jekyll does not have a client-side router. It renders static HTML files. That is exactly why I like it.

But static HTML does not mean every click needs to reload the whole document.

The answer was [Turbo Frames](https://turbo.hotwired.dev/reference/frames).

## The boring version

You can add Turbo to a Jekyll site by loading the script:

```html
<script src="/assets/vendor/turbo.js" defer></script>
```

Or use a CDN:

```html
<script type="module" src="https://cdn.jsdelivr.net/npm/@hotwired/turbo@8.0.23/dist/turbo.es2017-esm.js"></script>
```

A [`jekyll-turbo`](https://rubygems.org/gems/jekyll-turbo/versions/0.1.0) gem already does roughly this: inject Turbo into your generated HTML.

That is useful. But not the interesting part.

Turbo Drive is the default mode: click a link, fetch the next page, replace the document body, keep some browser state. It can make ordinary sites feel faster with almost no work.

But for a docs site, Turbo Drive is still too broad. I did not want to replace the whole body. Just the document content.

That is where Turbo Frames fit.

## The frame boundary

A Turbo Frame is just a custom HTML element with an id:

```html
<turbo-frame id="docs-content">
  ...
</turbo-frame>
```

When a link targets that frame, Turbo fetches the destination page, looks for a frame with the same id in the response, extracts it, and swaps only that piece into the current page.

That sentence contains the whole trick.

Every page you want to navigate to through the frame must render the same frame id.

In Jekyll, that means the frame belongs in the layout, not in one page:

{% raw %}
```liquid
<!DOCTYPE html>
<html>
  {% include head.html %}
  <body>
    {% include nav.html %}
    {% include sidebar.html %}

    <main id="content">
      <turbo-frame id="docs-content" target="_top">
        {{ content }}
      </turbo-frame>
    </main>
  </body>
</html>
```
{% endraw %}

The `target="_top"` part matters. It makes ordinary links inside the frame behave like normal full-page navigation unless you explicitly opt them into frame navigation. I prefer that. Turbo should be a progressive enhancement, not a trap.

Then you opt in the links that should update the docs content:

{% raw %}
```liquid
<a
  href="{{ doc.url | relative_url }}"
  data-turbo="true"
  data-turbo-frame="docs-content"
  data-turbo-action="advance">
  {{ doc.title }}
</a>
```
{% endraw %}

`data-turbo-frame` tells Turbo which frame to replace. `data-turbo-action="advance"` tells Turbo to push a new browser history entry instead of silently changing the frame in place. Without that, your docs navigation will feel broken the moment someone hits the back button.

This is the core pattern:

1. Put a stable frame around the part of the page that should change.
2. Make every destination page render that same frame.
3. Target internal navigation links into the frame.
4. Let everything else be a normal link.

That gets you most of the way there.

## Don't Turbo everything

The mistake is to get excited and start targeting every link.

Don't do that.

Some links should always be normal:

- external links
- downloads
- anchor links on the same page
- links with `target="_blank"`
- links to pages that do not render the same frame
- anything explicitly marked `data-turbo="false"`

In my theme, I enhance page links with JavaScript too, because Markdown authors should not have to remember Turbo attributes for every internal doc link:

```js
function shouldTargetFrame(link) {
  const href = link.getAttribute("href")
  if (!href || href.startsWith("#")) return false
  if (link.hasAttribute("target")) return false
  if (link.hasAttribute("download")) return false
  if (link.getAttribute("data-turbo") === "false") return false

  let url
  try {
    url = new URL(href, window.location.href)
  } catch {
    return false
  }

  if (url.origin !== window.location.origin) return false

  const lastSegment = url.pathname.split("/").pop()
  const hasExtension = lastSegment && lastSegment.includes(".")
  if (hasExtension && !/\.html?$/.test(lastSegment)) return false

  return true
}

function enhanceFrameLinks() {
  document.querySelectorAll(".docs-content a[href]").forEach((link) => {
    if (!shouldTargetFrame(link)) return

    link.setAttribute("data-turbo", "true")
    link.setAttribute("data-turbo-frame", "docs-content")
    link.setAttribute("data-turbo-action", "advance")
  })
}
```

This is not magic. Just a careful filter.

Same-origin HTML pages get frame navigation. Everything risky stays boring.

## Disable Drive if you only want Frames

Turbo Drive and Turbo Frames can work together, but for this kind of docs shell I like making the boundary explicit.

```js
if (window.Turbo && window.Turbo.session) {
  window.Turbo.session.drive = false
}
```

That tells Turbo: do not intercept every page visit. Only handle the links I explicitly target into a frame.

Could you leave Drive on? Sure. For a blog, that might be enough. For a documentation app with persistent sidebar state, rebuilt outlines, search overlays, and a bunch of page-specific behavior, I want fewer implicit moving parts.

Fast navigation is good. Predictable navigation is better.

## The part people forget: page state

When you replace only a frame, the rest of the document does not change.

That is the point. It is also the problem.

The browser does not automatically update every piece of state you used to get from a full page load. Your nav does not magically know which page is active. Your sidebar does not know which group to highlight. Your "On this page" outline still points at the old headings unless you rebuild it. Any copy buttons, anchors, syntax widgets, or page-specific behavior need to be initialized again.

I use a tiny hidden state node inside the frame:

{% raw %}
```liquid
{% assign page_title = site.title %}
{% if page.title and page.title != site.title %}
  {% capture page_title %}{{ page.title }} | {{ site.title }}{% endcapture %}
{% endif %}

<turbo-frame id="docs-content" target="_top">
  <div
    id="page-state"
    hidden
    data-title="{{ page_title | strip | escape }}"
    data-url="{{ page.url | relative_url }}"
    data-collection="{{ page.collection | default: '' | escape }}">
  </div>

  {{ content }}
</turbo-frame>
```
{% endraw %}

Then after the frame loads:

```js
document.addEventListener("turbo:frame-load", (event) => {
  if (event.target.id !== "docs-content") return

  const state = document.getElementById("page-state")
  if (state && state.dataset.title) {
    document.title = state.dataset.title
  }

  enhanceFrameLinks()
  updateActiveNavigation()
  rebuildOutline()
  addCopyButtons()

  if (window.location.hash) {
    document.querySelector(window.location.hash)?.scrollIntoView()
  } else {
    window.scrollTo({ top: 0, left: 0, behavior: "auto" })
  }
})
```

The exact functions are theme-specific. The lifecycle is not.

After a frame navigation, re-sync the stuff outside the frame that depends on the page inside the frame.

That is the whole mental model.

## Missing frames should fail normally

Turbo expects the response to contain the frame it was targeting. If you click a link targeting `docs-content`, the destination page needs:

```html
<turbo-frame id="docs-content">
  ...
</turbo-frame>
```

If it does not, Turbo treats that as an error. That is correct. It protects you from replacing your docs content with a random page that was never designed for the frame.

But users should not see a broken frame because one link escaped the docs section.

Handle the missing-frame event and fall back to a normal visit:

```js
document.addEventListener("turbo:frame-missing", (event) => {
  if (event.target.id !== "docs-content") return

  event.preventDefault()

  if (event.detail && typeof event.detail.visit === "function" && event.detail.response) {
    event.detail.visit(event.detail.response)
    return
  }

  if (event.detail && event.detail.response && event.detail.response.url) {
    window.location.href = event.detail.response.url
  }
})
```

Now frame navigation is a fast path, not a cliff.

If the page supports the frame, you get the app-like swap. If it does not, the browser does what browsers have done well for 30 years: load the page.

## So should this be a gem?

Part of it, yes.

A gem can reasonably do this:

- ship or inject Turbo
- provide a configurable frame include
- add helpers for frame-targeted links
- provide a small JavaScript file for safe internal link targeting
- handle missing-frame fallback
- dispatch lifecycle events after frame navigation

But a gem cannot know your layout.

It cannot know which part of your page is the shell and which part is content. It cannot know how your nav marks active links. It cannot know how your search modal, outline, theme switcher, analytics, or code block widgets should reinitialize.

That is why I think the pattern matters more than the gem.

`jekyll-turbo` as "load Turbo for me" is fine. A richer gem might be useful too. But the real work is choosing the frame boundary and being honest about what needs to happen after that boundary changes.

Static sites do not need to feel static. They also do not need to become SPAs.

Jekyll can render the pages. Turbo can move one frame. Your theme can keep the shell alive.

That is the sweet spot.
