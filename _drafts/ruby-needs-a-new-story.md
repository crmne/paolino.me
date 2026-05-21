---
layout: post
title: "Ruby Needs a New Story"
date: 2026-05-21
description: "Ruby doesn't need nostalgia. It needs a sharper public story, a better beginner path, and the confidence to own AI-era product development."
tags: [Ruby, Rails, AI, Developer Experience, Open Source]
---

Ruby doesn't need another "is Rails dead?" post.

I'm tired of that frame. It's boring, and it's wrong.

Ruby isn't dead. Rails isn't dead. People are still building serious things with both. Shopify, GitHub, 37signals, Cookpad, Doximity, Fleetio, Intercom, all the usual names. You know the list.

But something did happen.

Ruby stopped being obvious.

That's the problem. Not capability. Not scale. Not whether you can build a real business on Rails. Of course you can. The problem is that a new developer can spend a year learning web development, AI tools, deployment, databases, and product engineering without Ruby ever entering the conversation.

That should bother us.

## The Numbers Are Not A Funeral

[RedMonk still had Ruby at #9 in January 2026](https://redmonk.com/sogrady/2026/04/14/language-rankings-1-26/). That's not exactly a corpse.

But the learner numbers are ugly. In the [2025 Stack Overflow Developer Survey](https://survey.stackoverflow.co/2025/technology), Ruby showed up with 6.4% of all respondents, 6.9% of professional developers, and only 3.7% of people learning to code. Rails had the same shape: 6.2% of professional developers, but only 3.0% of learners.

That's the alarm bell.

Existing teams still use Ruby. Professionals still get paid to write Ruby. Big systems still run on Ruby. But the beginner pipeline is thin.

[JetBrains says Ruby is in steady decline](https://blog.jetbrains.com/research/2025/10/state-of-developer-ecosystem-2025/). I don't think we should hand-wring about that, but we also shouldn't pretend it's fake. JavaScript and TypeScript captured the web learner path. Python captured AI and data. Go captured a lot of the "serious backend" imagination. Rust captured the prestige slot.

Ruby kept being good.

That wasn't enough.

Good things still need distribution.

## We Hide The Good Parts

When I came back to Ruby in 2024, I kept running into this strange feeling: the ecosystem was much better than its reputation.

Ruby LSP exists. Async Ruby is real. Rails 8 is a full-stack answer in a world full of glue. Kamal makes deployment understandable again. Hotwire is still one of the best ideas in web development. YJIT changed the performance conversation. RubyLLM exists now because I wanted an AI library that felt like Ruby, not a translated Python API.

The ingredients are there.

But if you're not already inside the Ruby world, how would you know?

The outside story is still something like this:

Rails was cool in 2009. Ruby is slow. Dynamic languages are risky. Monoliths do not scale. The community is old. The front-end story is confusing. If you're doing AI, use Python. If you're doing web, use TypeScript.

Some of that is wrong. Some of it is outdated. Some of it is our fault.

Because if people still believe Rails can't scale after Shopify and GitHub, the problem isn't the evidence. The evidence exists.

[Shopify's Rails monolith powered $14.6 billion in merchant sales during Black Friday 2025](https://rubyonrails.org/foundation/shopify), with 489 million requests per minute on the edge and over 53 million database queries per second.

[GitHub.com is a Rails monolith](https://github.blog/engineering/architecture-optimization/building-github-with-ruby-and-rails/) with nearly two million lines of code, more than 1,000 engineers working on it, deployments as often as 20 times a day, and Rails upgrades nearly every week.

At some point, if the myth survives the receipts, the receipts aren't loud enough.

## Marketing Is Not A Dirty Word

Developers love pretending marketing is what you do when the product isn't good enough.

Bullshit.

Marketing is how people find out the product is good.

The Rails Foundation said this plainly when it launched. The ecosystem needed better [documentation, education, marketing, and events](https://rubyonrails.org/2022/11/14/the-rails-foundation), because the case for Rails was not being made well enough.

Exactly.

Great code doesn't speak for itself. It sits in a repository until someone explains why it matters. A beautiful framework doesn't magically enter a junior developer's YouTube recommendations. A production case study doesn't help anyone if it's buried three clicks deep and never repeated.

We should stop being embarrassed about this.

Ruby needs better marketing. Not fake hype. Not conference-keynote nonsense. Not "we are so back" posts every six months.

Clear, repeated, evidence-backed storytelling.

The boring kind that works.

## AI Is The Opening, But Not In The Cringe Way

Ruby isn't going to beat Python at model training.

Fine.

Most companies aren't training models. They are calling APIs.

The model call isn't the product. It's one weird HTTP request in the middle of a normal software business. The rest is users, permissions, billing, files, background jobs, streaming UI, retries, audits, admin screens, deployment, observability, support tools, and all the boring stuff that makes software real.

That's Rails territory.

This is why I think Ruby has an actual opening right now. Not because AI magically makes every old Ruby argument true again. Not because "agents love Ruby" or whatever the next slogan is.

Because AI makes code cheaper to produce and more expensive to understand.

That changes the value of Rails.

An LLM can generate a lot of code very quickly. Great. It can also generate five naming schemes, three service object styles, a random dependency, a controller that should have been a model method, a model method that should have been a query object, and a pile of front-end state that duplicates your backend state because it saw that pattern somewhere.

Rails pushes back against that.

Conventions matter more when the code was generated by something with no taste. Boring file locations matter. Boring names matter. Integrated defaults matter. Server-rendered HTML matters. A framework that says "put this here" matters.

People talk about TypeScript being good for agents because types give the machine and the reviewer more structure. That argument is real. [GitHub's 2025 Octoverse](https://github.blog/news-insights/octoverse/octoverse-a-new-developer-joins-github-every-second-as-ai-leads-typescript-to-1/) says TypeScript overtook both Python and JavaScript on GitHub, and explicitly connects that rise to agent-assisted coding and typed contracts.

Good. Take it seriously.

Then make the Ruby argument just as clearly:

Rails is the best way for a small team to build an AI product that doesn't turn into a pile of glue.

That's the story.

Not "Ruby is cute."

Not "Rails is still alive."

Not nostalgia.

Small teams. Real products. Less glue. Code you can still understand after the demo becomes a business.

## Teach Current Rails

The beginner path has to stop feeling like archaeology.

I don't want another tutorial that builds a toy blog, stops before deployment, and quietly assumes the reader will figure out the hard parts later.

Teach Rails as it exists now.

Rails 8. Hotwire. Kamal. Solid Queue. Solid Cache. Authentication. SQLite where it makes sense. PostgreSQL where it makes sense. Background jobs. File uploads. Email. AI streaming. Deployment. Monitoring. Tests that catch real mistakes.

A beginner should be able to go from zero to a deployed, modern Rails app without assembling the curriculum from old blog posts, abandoned screencasts, Reddit comments, and vibes.

This isn't just education. This is infrastructure.

The first day matters. If the editor feels broken, the docs look old, the tutorial doesn't deploy, and the recommended path forks into twelve opinions, people leave. They don't write an essay about it. They just pick the thing that felt alive.

Ruby has to feel alive in the first hour.

## Make The Front-End Story Obvious

Rails has a front-end story. We just make people work too hard to understand it.

React is legible. Next.js is legible. TypeScript everywhere is legible.

Rails needs the same clarity.

Use plain Rails until you need interactivity.

Use Hotwire when the server owns the state and the UI should feel alive.

Use Stimulus when a small behavior belongs in the browser.

Use a separate front end when the product actually needs one.

That should be everywhere. In docs. In talks. In starter apps. In decision trees. In examples. In the default mental model.

The point isn't to dunk on React. React is fine. The point is to stop losing people because the Rails answer is hidden behind community intuition.

## Show Receipts

Every Ruby argument should come with production evidence.

Not vibes. Not "trust me." Not "developer happiness" floating by itself.

Show the team size. Show the deploy flow. Show the architecture. Show the upgrade path. Show what stayed in the monolith. Show what got extracted. Show the boring maintenance work. Show the failure modes. Show what Rails made easy and what hurt.

Shopify shouldn't be a fun fact Rubyists throw into arguments. It should be impossible to research Rails without seeing that story.

Same for GitHub.

Same for every serious Rails company willing to talk.

The anti-Ruby narrative is old and lazy. Kill it with specifics.

## Make The Community Bigger Than Its Loudest Voices

Ruby shouldn't depend on one person, one company, one conference, one country, or one personality style.

That's too fragile.

We need more public faces. Maintainers. Educators. Founders. Staff engineers. Designers. Documentation people. Tool builders. Junior developers. People building boring profitable businesses. People building strange ambitious things. People outside the US. People who don't sound like the usual Ruby internet.

This matters more than people admit.

Communities grow when newcomers can see someone and think: there's a place for me here.

## Build For Agents Without Making Ruby Weird

We should absolutely make Ruby better for AI-assisted development.

Write docs that humans and agents can both follow. Keep examples current. Make generators produce idiomatic code. Make error messages teach. Make Ruby LSP excellent. Make Rails conventions explicit enough that tools can stay inside the lines. Build libraries like [RubyLLM](https://rubyllm.com/) that make AI product work feel native to Ruby instead of imported from another ecosystem.

But please, no cringe.

Do not call everything AI-native. Do not pretend experimental compiler work changes production Rails overnight. Do not claim Ruby has already won the AI era. Do not put a robot sticker on an old abstraction and call it strategy.

Just make the stack genuinely good for how people build now.

That's enough.

## The Standard Is Not Survival

Ruby can survive for decades.

Lots of languages survive. That's not the goal.

I want Ruby to be chosen on purpose by ambitious people building new things.

I want a founder with two engineers and a frighteningly large idea to look at Rails and think: yes, this is how we ship.

I want a new developer building their first serious app to see Ruby as modern, alive, and worth learning.

I want the AI product conversation to include Rails by default, because most AI products are web apps with business logic, not research notebooks.

That's our lane.

We don't need to become Python.

We don't need to become TypeScript.

We need to become obvious again.
