---
layout: post
title: "Your app owns chats and messages in RubyLLM 2.0"
description: "Your Rails app keeps Chat and Message in RubyLLM 2.0. RubyLLM manages its model registry, tool calls, usage, and batches through supporting tables."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

After installing RubyLLM 2.0 in Rails, your application has two models to work with:

```ruby
# app/models/chat.rb
class Chat < ApplicationRecord
  acts_as_chat
end

# app/models/message.rb
class Message < ApplicationRecord
  acts_as_message
  has_many_attached :attachments
end
```

Add your user associations, scopes, authorization, and retention rules to those models. They're the conversations your product manages.

The model registry, tool calls, usage, and batches live in RubyLLM's supporting tables. You read them through the public API:

```ruby
RubyLLM.models.find("gpt-5.4", provider: :openai)
message.tool_calls
message.tokens.input
chat.cost.total
RubyLLM::Batch.find(batch_id)
```

That's two fewer application models than a fresh 1.16 install. I'm happy to delete that bookkeeping from the app.

## Why Move the Tables?

In 1.x, the install generator created `Model` and `ToolCall` alongside `Chat` and `Message`. It also put token columns on messages.

That made RubyLLM's storage your responsibility. A change to tool-call persistence meant updating a model in your application, even if your application never used it directly.

Active Storage already gives us a useful precedent: the framework owns its supporting records, while the application uses them through attachments. RubyLLM can do the same for its registry and tool calls.

The supporting tables are:

| Table | Stores |
|---|---|
| `ruby_llm_models` | Model registry entries |
| `ruby_llm_tool_calls` | Tool calls, approval decisions, and result links |
| `ruby_llm_usages` | Provider attempts, tokens, and frozen costs |
| `ruby_llm_batches` | Persisted batch state |

They're ordinary tables installed by Rails migrations. Their record classes are internal; the application API is `RubyLLM.models`, `message.tool_calls`, `chat.cost`, and `RubyLLM::Batch`.

## Usage Needs Its Own Rows

A message can take several provider attempts to produce. A cancelled attempt may produce no message at all. That is why usage belongs in its own table.

With `acts_as_chat`, RubyLLM saves a finished attempt before the message callback. `chat.cost.total` includes retries and cancellations when their costs can be established, and returns `nil` when the complete total is unknown.

Your messages keep their content, attachments, citations, and other conversation data. Model and provider identity for an assistant response come through its usage entries.

## Upgrading the Existing Tables

Generate the upgrade:

```bash
bin/rails generate ruby_llm:upgrade
```

The current generator expects the 1.16 schema and writes three migrations: prepare, backfill, and finish. The default preparation renames the model and tool-call tables in place, creates the new supporting tables, and adds the 2.0 fields. Backfill converts content, result links, and historical usage. Finish verifies the conversion and applies the required constraints.

You can choose `--mode copy` instead. That retains the old supporting tables and model reference, and generates a compatibility concern and initializer for **both** the 2.0 app and its 1.16 rollback build. When 2.0 writes to a conversation, it stays stored but hidden and protected during a 1.16 rollback. Returning to 2.0 makes it available again and reconciles conversations used by 1.16.

Copy mode needs extra storage and backfill time. Its compatibility guards serialize ordinary writes through a short lock; they don't dual-write transcripts or support mixed-version writers. Custom foreign keys, callback-bypassing writes and attachment purges need special care. The [upgrade walkthrough](/rubyllm-2-0-upgrading/) explains the `rollback`, `resume`, and `finalize` commands and their limits.

Rehearse on a recent database copy. Keep affected web requests and background activity paused through all three phases and your application's own conversions. After migrating, load the packaged registry:

```bash
bin/rails db:migrate
bin/rails ruby_llm:load_models
```

In the 2.0 build, remove the old `Model` and `ToolCall` classes, their `acts_as_model` and `acts_as_tool_call` declarations, and the obsolete `config.model_registry_class` and `config.use_new_acts_as` settings. Update the surviving `acts_as` declarations too: old `model:` and `tool_calls:` options are no longer accepted.

The upgrade either renamed or preserved their tables, so deleting the 2.0 application's classes doesn't call for another migration to drop the data. Keep the original classes in a copy-mode 1.16 rollback build.

Legacy message columns stay in place until you've verified the upgrade. Remove them in a later deployment. In rename mode:

```bash
bin/rails generate ruby_llm:upgrade --phase cleanup
bin/rails db:migrate
```

In copy mode, stop affected activity and run `bin/rails ruby_llm:upgrade:finalize` before generating cleanup with `--mode copy --phase cleanup`. Finalization closes the rollback window; cleanup removes the preserved legacy tables. The [upgrade walkthrough](/rubyllm-2-0-upgrading/) covers the full sequence, custom model names, and data checks.

## Keep Your Application's Model Settings

Some apps added availability flags, defaults, or admin pricing to the old model table. Those are useful application features. Give them a table of their own, keyed by model ID and provider.

The upgrade preserves extra columns physically, but RubyLLM doesn't maintain those settings. Copy and reconcile them in an application migration before removing the originals. The same applies to custom accounting, evaluations, or foreign keys that refer to the old tables.

RubyLLM can then evolve its storage through upgrade migrations, while your product code works with chats, messages, and your own settings. The [Rails persistence guide](https://rubyllm.com/next/rails-persistence/) shows the associations and readers.
