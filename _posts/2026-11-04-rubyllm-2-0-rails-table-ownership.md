---
layout: post
title: "RubyLLM 2.0: Two Models in Your Rails App, Not Four"
date: 2026-11-04
description: "In RubyLLM 2.0 your Rails app keeps Chat and Message. RubyLLM owns its model registry, tool calls, usage, and batches in tables of its own."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

Remember the tree from the [1.14 chat UI post](/rubyllm-1-14-chat-ui/)? A fresh RubyLLM install put four models in your app:

```
app/models/
├── chat.rb
├── message.rb
├── model.rb
└── tool_call.rb
```

In 2.0 it's two:

```ruby
# app/models/chat.rb
class Chat < ApplicationRecord
  acts_as_chat
  belongs_to :user
end

# app/models/message.rb
class Message < ApplicationRecord
  acts_as_message
  has_many_attached :attachments
end
```

That's the whole persistence setup. No `Model`, no `ToolCall`, no `Batch`, no usage model. Chats and messages are your product's conversations, so they stay yours: users, scopes, authorization, titles, retention, all of it goes there like before.

Everything else lives in tables RubyLLM owns, and you read it through the same API you use in plain Ruby:

```ruby
RubyLLM.models.find("gpt-5.6", provider: :openai)
message.tool_calls
message.tokens.input
chat.cost.total
RubyLLM::Batch.find(batch_id)
```

## Why the Split

`Model` and `ToolCall` were never really your models. I wrote them, the generator copied them into your app, and from then on they were your problem. When RubyLLM needed to store something new about a tool call, you had to update a class you didn't write and never called directly.

2.0 stores a lot more. Tool calls carry approval decisions. Every provider attempt gets a usage row. Batches persist their state so another process can pick them up. Shipping all of that as "please update these four files in your app" would have been a terrible upgrade, and the next feature would have needed another one.

Rails already solved this. You don't have an `ActiveStorageBlob` in `app/models`. Active Storage owns its records and you use them through `has_many_attached`. RubyLLM now works the same way:

| Table | Stores |
|---|---|
| `ruby_llm_models` | The model registry |
| `ruby_llm_tool_calls` | Tool requests, approval decisions, and links to their results |
| `ruby_llm_usages` | One row per provider attempt: tokens and the cost at the time |
| `ruby_llm_batches` | Provider batch state |

They're ordinary tables created by ordinary migrations, not an engine. The record classes behind them are internal. The public surface is `RubyLLM.models`, `message.tool_calls`, `tokens`, `cost`, and `RubyLLM::Batch`, which means I can change how they're stored without your app noticing.

## Usage Gets Its Own Rows

In 1.x, token counts were columns on your messages. That works until you notice that a message and a provider call aren't the same thing.

A response can take three attempts because the first two hit a rate limit. A user can hit stop halfway through a stream, and the tokens you already paid for produce no message at all. Columns on `messages` can't record either.

So 2.0 writes one row per physical attempt, before the message callbacks run, so cancelling can't erase it. `chat.cost.total` includes the retries and the cancellations. When RubyLLM can't price something, the total is `nil` instead of a confident zero. A missing price should look missing, not free.

And because the usage is just rows with a `total_cost` column, your own reporting is plain Active Record:

```ruby
class User < ApplicationRecord
  has_many :chats
  has_many :ruby_llm_usages, through: :chats
end

current_user.ruby_llm_usages.sum(:total_cost)
```

## Upgrading From 1.16

The 2.0 upgrade generator expects the 1.16 schema and writes three migrations: prepare, backfill, and finish.

```bash
bundle add ruby_llm --version 2.0.0
bin/rails generate ruby_llm:upgrade
```

The default mode renames your existing model and tool-call tables into RubyLLM's ownership, creates the new tables, and backfills message content, tool-result links, and historical usage. Finish verifies the conversion and applies the constraints. Your chats and messages keep their IDs and relationships.

If you want a way back, `--mode copy` keeps the 1.16 tables alongside the new ones, generates compatibility code for both builds, and gives you `ruby_llm:upgrade:rollback` and `ruby_llm:upgrade:resume` tasks. Copy mode also lets prepare and backfill run while 1.16 keeps serving traffic. On the benchmark in the upgrade guide (100,000 synthetic chats, 1 million messages, PostgreSQL), rename took 20 seconds with AI paused the whole time, and online copy took 136 seconds in total but only 4 of them with AI paused. Pick based on what your app can tolerate, and rehearse either one on a recent copy of your database.

Then run it with AI requests and jobs paused:

```bash
bin/rails db:migrate
bin/rails ruby_llm:load_models
```

In the 2.0 app, delete `Model` and `ToolCall` along with their `acts_as_model` and `acts_as_tool_call` declarations. Drop the `model:` and `tool_calls:` options from `acts_as_chat` and `acts_as_message`, and remove `config.model_registry_class` and `config.use_new_acts_as` from your initializer. Don't drop the tables yourself: the migration already renamed or copied them.

The old message columns stay until you're sure. In a later deployment, `bin/rails generate ruby_llm:upgrade --phase cleanup` removes them. In copy mode, run `bin/rails ruby_llm:upgrade:finalize` first, which closes the rollback window.

That's the short version. The [2.0 upgrade guide](https://github.com/crmne/ruby_llm/blob/v2.0.0/docs/_reference/upgrading.md) covers custom model names, large databases, deployment timeouts, and the full copy-mode procedure. Now that 2.1 is out, upgrade a 1.x app to 2.0 first, then to 2.1. From 2.1 on, each release ships the upgrade from the one before it.

## If You Added Your Own Columns

Some apps put availability flags, default models, or admin pricing on the old `models` table. Those are real product features, but they belong to your product, not to RubyLLM's registry. Give them a table of your own, keyed by provider and model ID, and copy the values over before cleanup. Rename mode keeps the extra columns physically, but RubyLLM won't maintain them. The same goes for your own foreign keys, billing ledgers, or evaluations that point at the old tables.

After that, the boundary is clean. Your code works with chats, messages, and your own settings. RubyLLM evolves its storage through its own migrations. 2.1 already uses that freedom: it adds tables for MCP credentials and provider uploads, and lets RubyLLM's records follow your chats onto a secondary database.

The [Rails persistence guide](https://rubyllm.com/rails-persistence/) shows every association and reader.
