---
layout: post
title: "RubyLLM 1.14: From Zero to AI Chat App in Under Two Minutes"
date: 2026-03-18
description: "RubyLLM 1.14 ships a Tailwind chat UI, Rails generators for agents and tools, and a simplified config DSL. Watch the full setup in 1:46."
tags: [Ruby, AI, Rails, LLM, Open Source, RubyLLM, Chat UI]
video: https://talks.paolino.me/rucoco-2026/demo.mp4
---

I recorded a demo. New Rails app, install RubyLLM, run two generators, and you have a working AI chat application with streaming, model selection, and tool call display. The whole thing takes one minute and forty-six seconds.

Watch it. That's the pitch. That's the post.

---

Okay fine, there's more.

## The Chat UI

The new `ruby_llm:chat_ui` generator produces a complete Tailwind-powered chat interface. Not a scaffold you need to fight with. Not a starting point that falls apart the moment you look at it sideways. A real UI with role-aware message partials, Turbo Stream templates for real-time updates, model selection, and proper empty states.

```bash
bin/rails generate ruby_llm:chat_ui
```

The generated views use separate partials for each message role -- `_user`, `_assistant`, `_system`, `_tool`, `_error` -- so tool calls render differently from assistant responses, and error states don't just dump a stack trace. It uses `broadcasts_to` for simplified broadcasting, which means your chat updates are real-time out of the box.

This is the UI I wanted when I started building [Chat with Work](https://chatwithwork.com). The one that doesn't exist in the Ruby ecosystem because everyone assumes you'll build your own. Now you don't have to.

## Rails AI Generators

The chat UI isn't the only new generator. 1.14 adds scaffolding for the things you'll build next:

```bash
bin/rails generate ruby_llm:agent SupportAgent
bin/rails generate ruby_llm:tool WeatherTool
```

These create files in `app/agents`, `app/tools`, and `app/schemas` -- conventional directories that the install generator now sets up with `.gitkeep` files. The tool generator produces matching specs. The agent generator gives you a class with the DSL from [1.12](/rubyllm-1-12-agents/) ready to fill in.

It's the kind of thing Rails has always done well: make the boring parts automatic so you can focus on the interesting parts.

## Self-Registering Provider Config

This one is for the people building provider gems. The configuration system used to have a monolithic list of `attr_accessor`s in the `Configuration` class. Every time someone added a provider, they had to patch that file.

Now providers register their own options:

```ruby
class DeepSeek < RubyLLM::Provider
  class << self
    def configuration_options
      %i[deepseek_api_key deepseek_api_base]
    end
  end
end
```

When the provider is registered, its options become `attr_accessor`s on `RubyLLM::Configuration` automatically. Third-party provider gems can add their config keys without touching the core. Convention over configuration, applied to configuration itself.

## Bug Fixes

A batch of fixes that matter more than they sound:

- **Faraday logging memory bloat** -- logging no longer serializes large payloads (like base64-encoded PDFs) when the log level is above DEBUG. If you were wondering why your memory usage spiked on every request, this was it.
- **Agent `assume_model_exists` propagation** -- setting this on the agent class now actually works.
- **Renamed model associations** -- foreign key references with `acts_as` helpers are fixed.
- **MySQL/MariaDB compatibility** -- JSON column defaults work correctly now.
- **Error.new with string argument** -- no longer raises a `NoMethodError`, which was embarrassing.

The full list is in the [release notes](https://github.com/crmne/ruby_llm/releases/tag/1.14.0).

## The Point

I keep coming back to the same thing: AI tooling for Ruby developers should feel like Ruby. Not like a Python library with Ruby bindings. Not like a JavaScript framework ported to a gem. Like Ruby.

Two generators and you have a streaming AI chat app with Tailwind, Turbo, and tool support. That's what 1:46 looks like.

```ruby
gem 'ruby_llm', '~> 1.14'
```
