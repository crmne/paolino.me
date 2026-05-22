---
layout: post
title: "Ruby Needs a New Story"
date: 2026-05-21
description: "Ruby doesn't need nostalgia. It needs to become obvious again in the age of AI-generated software."
tags: [Ruby, Rails, AI, Developer Experience, Open Source]
---

I was talking with Irina from Evil Martians recently, and she asked a simple question

> What should we do, as a Ruby community?

My answer was boring.

> Marketing.

Not launch culture, not slogans, not fake hype, but the kind of marketing that makes the case clearly, shows the work, and gives people coming in from outside a path that does not feel like digging. The technology is great. We have Rails 8, Hotwire, Hotwire Native, Kamal, Solid Queue, Solid Cache, Solid Cable, YJIT, fibers, Ruby LSP, and RubyLLM, on top of twenty years of production knowledge in the ecosystem. The problem is that not enough people outside the Ruby community know why any of it matters now.

## The Decline Is Real

[RedMonk had Ruby at #9 in January 2026](https://redmonk.com/sogrady/2026/04/14/language-rankings-1-26/), so this is not a funeral. But the learner numbers are bad. In the [2025 Stack Overflow Developer Survey](https://survey.stackoverflow.co/2025/technology), Ruby showed up with 6.9% of professional developers and only 3.7% of people learning to code. Rails had the same shape: 6.2% of professionals, 3.0% of learners.

Ruby still has professionals, companies, and serious systems. What it doesn't have enough of is new gravity, and from the outside that gap looks like age. That's the marketing failure.

## Ruby Is Perfect For Generated Code

Everybody is generating more code now. Call it agentic engineering, vibe coding, AI-assisted development, whatever you like. When writing code gets cheap, reading code becomes the actual work. When an LLM generates something, I have to see the shape, find where the logic lives, notice when the abstraction is wrong, and review it before it ships. Good Ruby reads close to intent, close to pseudocode, and Rails gives that code a predictable home: models here, controllers there, jobs, mailers, etc. Twenty years of training both humans and machines on the same structure.

The community is also full of senior engineers who care if an API feels right, if a method name is ugly, if a class exists only because someone thought every noun deserved a file. That is the kind of culture the AI era actually rewards, and Ruby has been quietly building it the whole time.

## Most AI Products Are Web Apps

Python owns model training, and it can keep it. Most companies are not training models. They are calling APIs, which means the actual model call is one weird HTTP request, and the product is everything around it: users, permissions, billing, files, background jobs, streaming UI, retries, audits, admin screens, deployment, observability, support tools, mobile shells.

That is the work Rails has been doing for twenty years. Hotwire renders on the server, sends it over the wire, and keeps state where state already lives, which happens to be exactly what streaming AI UIs want. Hotwire Native covers the mobile shell. Kamal covers deployment. Solid Queue covers background jobs. RubyLLM makes the model call itself feel like Ruby instead of an awkward translation from Python or JavaScript. None of that is a marketing claim. The stack is already here, in one ecosystem, with one set of conventions.

## Stop Apologizing For Scale

[Shopify's Rails monolith powered $14.6 billion in merchant sales during Black Friday 2025](https://rubyonrails.org/foundation/shopify), with 489 million requests per minute on the edge and over 53 million database queries per second. [GitHub.com is a Rails monolith](https://github.blog/engineering/architecture-optimization/building-github-with-ruby-and-rails/) with nearly two million lines of code, more than 1,000 engineers working on it, deployments as often as 20 times a day, and Rails upgrades nearly every week.

If that doesn't count as scale, the word has no meaning. The honest answer to "does Rails scale" is that it already has, and the right response is to keep showing the receipts until people stop repeating stale opinions from 2014.

## The Real Problem Is Documentation

The other thing we need, alongside the marketing, is much better documentation. The first hour of Rails matters more than any benchmark, and right now that first hour is rough. A new developer arrives, picks up Hotwire, picks up Hotwire Native, tries Async, and finds that the load-bearing parts of the ecosystem are under-documented or documented in the wrong places. The good answers exist, but they live scattered across blog posts, conference talks, abandoned screencasts, Reddit comments, and vibes.

Take the front-end story. The actual answer is simple: plain Rails until you need interactivity, Hotwire when the server owns the state, Stimulus for small browser behavior, and a separate front end only when the product really needs one. That should be the first thing a newcomer reads. Instead, getting to it requires absorbing years of community intuition. Hotwire, Hotwire Native, and Async all deserve documentation at the level of the code they describe, and they do not have it yet.

The same gap exists at the patterns layer. A newcomer to Ruby should be able to find one canonical place that explains how config modules work, how concerns are done well, what the 37signals way of building a Rails app looks like, and which credible alternatives exist alongside it. One place that people are happy to link other people to, instead of arguing about. The same goes for books and video series: the classics still exist, but they feel old and scattered, and the modern equivalents have not really been written yet.

This is not just about teaching. It is about distribution, because people who give up on Rails in the first hour rarely come back in year three.

## Ruby Needs More DevTool Companies

The other side of the marketing problem is structural, not personal. Most of the JavaScript marketing engine is not individuals on Twitter. It is hundreds of DevTool companies whose entire product is JavaScript tooling, and their combined marketing budget is, by extension, the language's marketing budget. Ruby has a lot of companies built on Rails, but most of them sell something else: commerce, code hosting, communication, accounting. They are not going to spend their marketing energy promoting the language itself, and that is fair, because the language is not their product.

Ruby missed the wave of DevTool companies that other ecosystems caught, and that gap is what now shapes how the outside world hears about us. The fix is not more slogans. It is more companies whose product is Ruby tooling, with real customers and a natural reason to make the Ruby case in public.

## Become Obvious Again

Ruby can keep surviving for decades. Survival is not the goal. The goal is to be chosen on purpose by ambitious people building new things. I want a founder with two engineers and a frighteningly large idea to look at Rails and think: yes, this is how we ship. I want the AI product conversation to start by default with Rails, because most AI products are web apps with business logic, not research notebooks.

The technology is already here. What is left is to make Ruby obvious again to everyone outside the room.
