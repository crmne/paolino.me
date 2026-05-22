---
layout: post
title: "Ruby Needs a New Story"
date: 2026-05-21
description: "Ruby doesn't need nostalgia. It needs to become obvious again in the age of AI-generated software."
tags: [Ruby, Rails, AI, Developer Experience, Open Source]
---

I was talking with Irina from Evil Martians recently, and she asked me a simple question:

What should we do, as a Ruby community?

Not "is Ruby dead?" Not "does Rails scale?" Not the usual tired stuff. A better question. What do we actually do?

My answer was boring.

Marketing.

I know. Nobody wants that answer. We want the answer to be a compiler, a framework feature, a benchmark, a new concurrency primitive, a technical move. And yes, all of that matters. But Ruby's problem is not that we don't have good technology.

We have excellent technology.

We have Rails. We have Hotwire. We have Hotwire Native. We have Kamal. We have Solid Queue, Solid Cache, Solid Cable. We have YJIT. We have fibers. We have Ruby LSP. We have RubyLLM. We have twenty years of production Rails knowledge sitting in the ecosystem.

The problem is that not enough people know why any of this matters now.

Ruby doesn't need to be rediscovered by its own community. Ruby needs to become obvious again to everyone else.

## The Decline Is Real

I don't think we should be dramatic about this, but we also shouldn't lie to ourselves.

[RedMonk still had Ruby at #9 in January 2026](https://redmonk.com/sogrady/2026/04/14/language-rankings-1-26/), so this is not a funeral. But the learner numbers are bad. In the [2025 Stack Overflow Developer Survey](https://survey.stackoverflow.co/2025/technology), Ruby showed up with 6.9% of professional developers and only 3.7% of people learning to code. Rails had the same shape: 6.2% of professional developers, but only 3.0% of learners.

That's the problem.

Ruby still has professionals. Ruby still has companies. Ruby still has serious systems. What it doesn't have is enough new gravity.

When I came back to Ruby in 2024, I could still read Rails code. I could still read Active Record. The framework had evolved, but the shape was familiar. That continuity is an enormous advantage for people inside the ecosystem.

From the outside, it can look like age.

That is the marketing failure.

## Ruby Is Perfect For Generated Code

The strongest Ruby argument right now is not nostalgia. It's not even speed.

It's readability.

Everybody is going to generate more code. Call it agentic engineering, vibe coding, AI-assisted development, whatever. The name doesn't matter. The direction is obvious: more software will be written with LLMs in the loop.

That makes reading code more important, not less.

If an LLM generates something, I need to understand it quickly. I need to see the shape. I need to know where the business logic lives. I need to notice when the abstraction is wrong. I need to review it before it becomes part of the product.

Ruby is ridiculously good at this.

Good Ruby reads close to intent. Rails gives it a predictable home. Models go here. Controllers go there. Jobs, mailers, channels, views, migrations, tests. The framework has been training both humans and machines on the same structure for almost twenty years.

That matters.

An LLM can generate Go. It can generate Rust. It can generate TypeScript. Fine. But if the result is something you have to inspect, change, and live with, readability is not decoration. It's the work.

And Rubyists care about this stuff.

We care if an API feels right. We care if a method name is ugly. We care if a class exists only because someone thought every noun deserved a file. We have a community full of senior people who have been building production software for a long time, inside one dominant framework that taught everyone similar instincts.

That is not a small thing.

The AI era rewards taste. Ruby has a culture of taste.

We should say that without mumbling.

## Rails Is The Product Stack For AI Apps

Python owns model training. Great. It can keep it.

Most companies are not training models. They are calling APIs.

The model call is one weird HTTP request. The product is everything around it: users, permissions, billing, files, background jobs, streaming UI, retries, audits, admin screens, deployment, observability, support tools, mobile shells.

That is Rails territory.

Rails is boring in exactly the right way. It gives you the product stack. Not just a router. Not just a rendering layer. Not just a database library. The whole thing.

And the new stuff fits the moment.

Hotwire is still one of the best front-end ideas we have. Render HTML on the server, send it over the wire, keep the state where the state already lives. For AI apps, where streaming and progressive UI matter, that model is incredibly natural. Hotwire Native gives you a way to wrap that same product in a mobile shell without pretending you suddenly have three products.

Kamal makes deployment understandable. Solid Queue means background jobs are part of the Rails answer. RubyLLM makes model APIs feel like Ruby instead of an awkward translation from Python or JavaScript.

This is the pitch:

Rails is the best way for a small team to build an AI product that doesn't turn into a pile of glue.

Not "Rails is still alive."

Not "remember 2009."

Small teams. Real products. Less glue. Code you can still understand after the demo becomes a business.

## Stop Apologizing For Scale

The "Rails doesn't scale" thing should be dead by now.

[Shopify's Rails monolith powered $14.6 billion in merchant sales during Black Friday 2025](https://rubyonrails.org/foundation/shopify), with 489 million requests per minute on the edge and over 53 million database queries per second.

[GitHub.com is a Rails monolith](https://github.blog/engineering/architecture-optimization/building-github-with-ruby-and-rails/) with nearly two million lines of code, more than 1,000 engineers working on it, deployments as often as 20 times a day, and Rails upgrades nearly every week.

If that doesn't count as scale, the word has no meaning.

Yes, there are old stories about companies banning Ruby, or people repeating that it doesn't scale, or Google culture pushing Python, or whatever. Maybe some of it mattered. Maybe some of it is true. Maybe some of it is telephone-game nonsense.

I don't think that should be our public story.

Our public story should be simpler:

Rails scales because Rails has scaled.

Then show the receipts until people stop repeating stale opinions from 2014.

## The Front-End Story Needs To Be Clearer

I think Rails has one of the better front-end stories. I also think we explain it badly.

React is legible. Next.js is legible. TypeScript everywhere is legible.

Rails needs the same clarity.

Use plain Rails until you need interactivity.

Use Hotwire when the server owns the state and the UI should feel alive.

Use Stimulus when a small behavior belongs in the browser.

Use a separate front end when the product actually needs one.

That should be obvious from the docs, tutorials, starter apps, conference talks, and examples. It should not require absorbing years of Ruby community intuition.

Also: the tooling has to keep improving. Hotwire is powerful, but the ergonomics are not always as good as the idea. That matters. The first hour matters. If the first hour feels old, confusing, or under-tooled, people leave before they ever reach the good part.

## Teach The Rails We Actually Have

The beginner path cannot be a museum.

I don't want another tutorial that builds a toy blog, stops before deployment, and quietly assumes the reader will figure out the hard parts later.

Teach Rails as it exists now.

Rails 8. Hotwire. Kamal. Solid Queue. Solid Cache. Authentication. SQLite where it makes sense. PostgreSQL where it makes sense. Background jobs. File uploads. Email. AI streaming. Deployment. Tests that catch real mistakes.

A beginner should be able to go from zero to a deployed, modern Rails app without assembling the curriculum from old blog posts, abandoned screencasts, Reddit comments, and vibes.

This isn't just education. It's distribution.

The first day is where languages win or lose.

## We Need Better Marketing, Not Fake Hype

Ruby people are suspicious of hype. Good.

But sometimes we confuse hype with saying the obvious loudly.

The JavaScript world oversells constantly. A new framework appears, calls itself the future of software, ships half-broken examples, and somehow gets a launch week. Ruby tends to do the opposite. We build something solid, mention it politely, and then act surprised when nobody outside the community notices.

That has to change.

Not by lying. Not by copying the worst parts of Silicon Valley launch culture. Not by calling everything AI-native.

By making the case clearly.

Ruby is readable. Rails is complete. Hotwire is a serious alternative to front-end sprawl. Rails scales. The ecosystem has taste. AI makes all of that more valuable.

Say it. Show examples. Show production numbers. Show beautiful docs. Show side-by-side comparisons. Show small teams shipping real products. Show the code.

Marketing is not a dirty word. Marketing is how good work becomes visible.

## Make The Community Bigger Than Its Loudest Voices

Ruby should not depend on one person, one company, one conference, one country, or one personality style.

That is too fragile.

We need more public faces: maintainers, educators, founders, staff engineers, designers, documentation people, tool builders, junior developers, people building boring profitable businesses, people building strange ambitious things, people outside the US, people who don't sound like the usual Ruby internet.

This matters more than people admit.

Communities grow when newcomers can see someone and think: there's a place for me here.

## Become Obvious Again

Ruby can survive for decades.

That's not the goal.

I want Ruby to be chosen on purpose by ambitious people building new things.

I want a founder with two engineers and a frighteningly large idea to look at Rails and think: yes, this is how we ship.

I want a new developer building their first serious app to see Ruby as modern, alive, and worth learning.

I want the AI product conversation to include Rails by default, because most AI products are web apps with business logic, not research notebooks.

We don't need to become Python.

We don't need to become TypeScript.

We need to become obvious again.
