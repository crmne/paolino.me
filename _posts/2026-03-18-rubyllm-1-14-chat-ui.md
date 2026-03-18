---
layout: post
title: "RubyLLM 1.14: From Zero to AI Chat App in Under Two Minutes"
date: 2026-03-18
description: "RubyLLM 1.14 ships a Tailwind chat UI, Rails generators for agents and tools, and a simplified config DSL. Watch the full setup in 1:46."
tags: [Ruby, AI, Rails, LLM, Open Source, RubyLLM, Chat UI]
image: /images/rubyllm-1.14.png
video: https://talks.paolino.me/rucoco-2026/demo.mp4
sendfox_campaign_id: 2750884
---
RubyLLM 1.14 ships a full chat UI generator. Two commands and you have a working AI chat app with Turbo streaming, model selection, and tool call display, in under two minutes. The demo above shows the whole thing: new Rails app to working chat in 1:46, including trying it out.

## Why This Matters

RubyLLM turned one last week. [1.0 shipped on March 11, 2025](/rubyllm-1-0/) with Rails integration from day one: ActiveRecord models, `acts_as_chat`, Turbo streaming, persistence out of the box. [1.4](/rubyllm-1.4-1.5.1/) added the install generator. [1.7](/rubyllm-1-7/) brought the first scaffold chat UI with Turbo Streams. [1.12](/rubyllm-1-12-agents/) introduced agents with prompt conventions. Each release got closer to the same thing: AI that works the way Rails works.

1.14 fully realizes that goal. A beautiful Tailwind chat UI (with automatic fallback to scaffold if you're not using Tailwind). Generators for agents and tools. Conventional directories for everything. All of it extracted from [Chat with Work](https://chatwithwork.com), where it's been running in production for months.

## What You Get

Two generators. That's it.

```sh
bin/rails generate ruby_llm:install
bin/rails generate ruby_llm:chat_ui
```

Your app now has this structure:

```
app/
├── agents/
├── controllers/
│   ├── chats_controller.rb
│   └── messages_controller.rb
├── helpers/
│   └── messages_helper.rb
├── jobs/
│   └── chat_response_job.rb
├── models/
│   ├── chat.rb
│   ├── message.rb
│   ├── model.rb
│   └── tool_call.rb
├── prompts/
├── schemas/
├── tools/
└── views/
    ├── chats/
    │   ├── index.html.erb
    │   ├── show.html.erb
    │   └── _chat.html.erb
    └── messages/
        ├── _assistant.html.erb
        ├── _user.html.erb
        ├── _tool.html.erb
        ├── _error.html.erb
        ├── create.turbo_stream.erb
        ├── tool_calls/
        │   └── _default.html.erb
        └── tool_results/
            └── _default.html.erb
```

Separate partials for each message role. Turbo Stream templates for real-time updates via `broadcasts_to`. A background job that handles the AI response. Tool calls and tool results each get their own rendering pipeline. A complete Tailwind chat interface, not a scaffold you need to fight with.

## Full Tutorial: New App from Scratch

If you want to start from zero, this is what the demo shows. The whole thing takes just a minute.

```sh
rails new chat_app --css tailwind
cd chat_app
bundle add ruby_llm
bin/rails generate ruby_llm:install
bin/rails generate ruby_llm:chat_ui
bin/rails db:migrate
bin/rails ruby_llm:load_models
bin/dev
```

That's a new Rails app with Tailwind, RubyLLM installed, the chat UI generated, the database set up, models loaded, and the server running. Open `localhost:3000/chats` and start talking to an AI.

## Generators for Agents, Tools, and Schemas

Now the fun part. You scaffold agents, tools, and schemas the same way you'd scaffold anything else in Rails:

```bash
bin/rails generate ruby_llm:agent SupportAgent
```

```
app/
├── agents/
│   └── support_agent.rb
└── prompts/
    └── support_agent/
        └── instructions.txt.erb
```

The agent class comes with the [1.12 DSL](/rubyllm-1-12-agents/) ready to go. The instructions file is an ERB template for your system prompt, so you can version it, review it in PRs, and template it with runtime context.

```bash
bin/rails generate ruby_llm:tool WeatherTool
```

```
app/
├── tools/
│   └── weather_tool.rb
└── views/
    └── messages/
        ├── tool_calls/
        │   └── _weather.html.erb
        └── tool_results/
            └── _weather.html.erb
```

Each tool gets its own partials for rendering calls and results. Show a weather widget for the weather tool, a search results list for a search tool, all through Rails partials.

```bash
bin/rails generate ruby_llm:schema Product
```

```
app/
└── schemas/
    └── product_schema.rb
```

This creates a schema for structured output validation.

More on all of this in the [Rails integration docs](https://rubyllm.com/rails/), and the dedicated guides for [agents](https://rubyllm.com/agents/) and [tools](https://rubyllm.com/tools/).

## Self-Registering Provider Config

For people building provider gems: providers now register their own configuration options instead of patching a monolithic `Configuration` class.

```ruby
class DeepSeek < RubyLLM::Provider
  class << self
    def configuration_options
      %i[deepseek_api_key deepseek_api_base]
    end
  end
end
```

When the provider is registered, its options become `attr_accessor`s on `RubyLLM::Configuration` automatically. Third-party gems can add their config keys without touching the core.

## Bug Fixes

- **Faraday logging memory bloat**: logging no longer serializes large payloads (like base64-encoded PDFs) when the log level is above DEBUG.
- **Agent `assume_model_exists` propagation**: setting this on the agent class now actually works.
- **Renamed model associations**: foreign key references with `acts_as` helpers are fixed.
- **MySQL/MariaDB compatibility**: JSON column defaults work correctly now.
- **Error.new with string argument**: no longer raises a `NoMethodError`.

Full list in the [release notes](https://github.com/crmne/ruby_llm/releases/tag/1.14.0).

```ruby
gem 'ruby_llm', '~> 1.14'
```
