---
layout: post
title: "Upgrading a Rails App to RubyLLM 2.0"
date: 2026-10-07
description: "Move a Rails app from RubyLLM 1.16 to 2.0: update your calls, migrate in phases, pick rename or copy mode, and clean up once you trust the result."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

[RubyLLM 2.0](/rubyllm-2-0/) changes the API and the Rails schema. I put a lot of work into the upgrade path.

Your chats and messages keep their IDs and relationships. Nothing gets deleted until you run cleanup. Every migration phase can be retried. And if you want a way back to 1.16 after going live, copy mode gives you one.

## Code and Data

There are two jobs: update your Ruby code, and, if you use Rails persistence, migrate your stored records. Plain Ruby apps only do the first one.

Start from a working 1.16 app. If you're on something older, step through the minor releases first. The generator expects the schema 1.16 produced; it doesn't guess how an older or customized one should map.

Two things to do while you're still on 1.16:

- Set `config.deprecation_behavior = :raise` in your test environment and fix whatever breaks. The setting was added in [1.16](/rubyllm-1-16/) to prepare for this upgrade.
- If you still have `config.use_new_acts_as = false`, switch to the association-based `acts_as` API now. 2.0 only has that one.

Then bring in 2.0, pinned to the 2.0 series:

```ruby
gem "ruby_llm", "~> 2.0.0"
```

```bash
bundle update ruby_llm
```

The pin matters. The 1.16 upgrade generator, its migration helpers, and the copy-mode tasks ship with 2.0 only. From 2.1 on, each release carries just the upgrade from the release before it. Finish this one, cleanup included, before you move on.

## Update Your Calls

Most of the code changes are renames. Each concept now has one name, and the old abbreviations are gone:

| 1.16 | 2.0 |
|---|---|
| `with_tool(Weather)` | `with_tools(Weather)` |
| `with_tools(W, choice: :required)` | `with_tools(W).with_tool_options(choice: :required)` |
| Tool `desc`, `param`, `params` | `description`, `parameter`, `parameters` |
| `with_params(...)`, `params:` | `with_provider_options(...)`, `provider_options:` |
| `response.input_tokens`, `response.output_tokens` | `response.tokens.input`, `response.tokens.output` |
| `tokens.reasoning` | `tokens.thinking` |
| `response.model_id` | `response.model` |
| `response.content` as a parsed Hash | `response.parsed`; `content` is the JSON string |
| `RubyLLM::Schema` | `Schematist::Schema` |
| `model.supports_vision?` | `model.supports?(:vision)` |
| `RubyLLM::Model::Info` | `RubyLLM::Model` |
| `RubyLLM.models.find(id, :openai)` | `RubyLLM.models.find(id, provider: :openai)` |
| `RubyLLM.models.refresh!` | `RubyLLM.models.refresh` |
| `create_user_message(content)` | `ask_later(content)` or `add_message(...)` |
| `chat.reset_messages!` | `chat.messages = []` |
| `on_new_message`, `on_end_message` | `before_message`, `after_message` |
| `on_tool_call`, `on_tool_result` | `before_tool_call`, `after_tool_result` |
| `tool.call({ city: "Berlin" })` | `tool.call(city: "Berlin")` |
| `transcribe(audio, response_format: "srt")` | `transcribe(audio, format: "srt")` |
| `halt`, `Tool::Halt` | Your own loop condition, or tool approval |

The upgrade guide has the complete table. A few behavior changes deserve a sentence each:

**Finish reasons are Symbols.** `:stop`, `:max_tokens`, `:tool_calls`, and `:content_filter`, normalized across providers. If you compared against `"end_turn"` or `"STOP"`, use the symbols or the readers: `stopped?`, `max_tokens?`, `tool_call_stop?`, `content_filtered?`.

**Switches and setters are consistent.** `with_thinking`, `with_caching`, `with_citations`, and `with_compaction` take `false` to turn off and reject `nil`. Value setters like `with_temperature` take `nil` to reset.

**Callbacks add up.** The new `before_` and `after_` callbacks stack. The old `on_*` ones replaced each other.

**OpenAI uses the Responses API.** If you pass Chat Completions-only options such as `response_format` through `with_provider_options`, move them to the Responses shape or set `config.openai_protocol = :chat_completions`.

**The temperature you set is the temperature sent.** 1.x sometimes rewrote it for certain models. If a model rejects your value, you'll now get a `RubyLLM::BadRequestError` from the provider.

Two notes for search-and-replace. Rails controller `params` have nothing to do with the `params:` rename, so change RubyLLM call sites one by one. And if you copied the old Rails attachment example that passes `params[:uploaded_file]` straight to `with:`, replace it with the [validated version](https://rubyllm.com/rails-persistence/#attachments-and-structured-output). Upgrading the gem doesn't fix application code.

Tried a release candidate? Rename `with_server_tools` to `with_provider_tools`, and the `server_tools` Agent macro to `provider_tools`.

## Rename or Copy

Now the database. The generator offers two modes.

**Rename** is the default. It moves your existing model and tool-call tables into RubyLLM's ownership. It's fast, makes no copies, and needs AI activity paused for all three phases. Going back to 1.16 means restoring your backup together with the matching app build.

**Copy** (`--mode copy`) leaves the 1.16 tables alone and builds the 2.0 ones next to them. Preparation and backfill run while 1.16 keeps serving traffic, so the pause shrinks to the final phase. It also keeps a supported route back to 1.16 until you decide to stay.

How different are they? On 100,000 synthetic chats with a million messages, on PostgreSQL:

| Mode | Total migration time | AI downtime |
|---|---:|---:|
| Rename | 20 s | 20 s |
| Copy | 136 s | 4 s |

Rename finishes sooner, and copy keeps you online for more of the migration. Those are medians from my [migration benchmark](https://github.com/crmne/ruby_llm_migration_bench), not a promise about your database: longer chats and live writes add work. Rehearse on your own data before choosing.

Copy mode has a price beyond disk space. It generates a compatibility concern and initializer that must run in both the 1.16 build and the 2.0 build. Those guards cover Active Record saves, updates, and destroys, but not `update_columns`, bulk SQL, direct deletes, or attachment purges, so review your own persistence code. Copy migrations also need a direct database connection or a session-mode pool, since their advisory locks don't work through transaction-mode pooling.

If you don't need the way back or the shorter pause, use rename, which is simpler.

## Generate the Migrations

```bash
bin/rails generate ruby_llm:upgrade               # rename
bin/rails generate ruby_llm:upgrade --mode copy   # copy
```

Custom class names? Pass every mapping that differs from the defaults:

```bash
bin/rails generate ruby_llm:upgrade \
  chat:AI::Chat \
  message:AI::Chat::Message \
  model:AI::LLMModel \
  tool_call:AI::Chat::ToolCall
```

The generator prints the classes and tables it resolved. Read that, then read the migrations. Use the same mappings and `--mode` every time you generate another phase.

You get three migrations:

| Phase | What it does | Old data |
|---|---|---|
| Prepare | Adds the 2.0 schema. Rename moves the supporting tables; copy creates new ones and a change journal. | Untouched in copy mode. |
| Backfill | Converts message content, tool-result links, and historical usage. | Legacy message columns kept. |
| Finish | Validates the conversion, enforces constraints, and activates 2.0. In copy mode, it first catches up writes made since backfill. | Legacy message columns kept. |

Cleanup is a fourth phase you generate later, after you trust the result.

The backfill works in batches of 10,000 messages and saves its progress with each one. If it stops, fix whatever it reported and run it again. Finished batches are skipped, and historical usage is never counted twice.

## Rehearse

Take a recent copy of production and the exact build you plan to deploy. Run the migrations there and time them, including prepare, which builds indexes. Then check what you care about: message counts, tool-result links, token counts, any costs you already store. Open a few old conversations with attachments and tool calls.

In copy mode, rehearse rollback and resume with both builds too.

## Run It

Take a backup you've actually restored before.

**Rename:** finish or cancel conversations waiting on tool results, then stop web requests, workers, scheduled jobs, and retries that touch AI. With the 2.0 code deployed and those still stopped:

```bash
bin/rails db:migrate
bin/rails ruby_llm:load_models
```

`load_models` imports the registry that ships with the gem, no network needed. Check the converted records like you did in rehearsal, then restart and reopen traffic.

**Copy** goes in four moves:

1. Deploy the generated concern and initializer to the running 1.16 app and restart every process, before any schema change.
2. From the 2.0 build, run prepare and backfill while 1.16 keeps serving. Keep 2.0's web processes and workers stopped. `bin/rails db:migrate VERSION=<backfill_timestamp>` stops there; a plain `db:migrate` would run finish too.
3. Pause AI requests and jobs, drain in-flight work, and finish or cancel pending tool calls, approvals, and batches. Run finish from the 2.0 build.
4. Run `bin/rails ruby_llm:load_models`, restart on 2.0, and reopen.

If finish refuses to run because of old tool calls that never got a result, the guide's [incomplete tool calls](https://github.com/crmne/ruby_llm/blob/v2.0.0/docs/_reference/upgrading.md#incomplete-tool-calls) section explains `--discard-incomplete-tool-calls`. Read it before using it: discarded calls don't come back.

If your deploy's migration step has a timeout, generate the phases one at a time with `--phase prepare`, `--phase backfill`, and `--phase finish`, and run them with `bin/rails db:migrate:up VERSION=...` in order from a process without that limit.

## Delete Two Models

In the 2.0 app, your `Chat` and `Message` stay:

```ruby
class Chat < ApplicationRecord
  acts_as_chat
end

class Message < ApplicationRecord
  acts_as_message
end
```

Delete the `Model` and `ToolCall` classes and their `acts_as_model` and `acts_as_tool_call` declarations. Remove `model:` and `tool_calls:` from the remaining macros, and `config.model_registry_class` and `config.use_new_acts_as` from the initializer. RubyLLM now owns those records under the `ruby_llm_` prefix: read them through `RubyLLM.models`, `message.tool_calls`, `message.tokens`, and `chat.cost`.

Don't drop the old tables yourself. The migrations renamed them or kept them for copy mode. And in copy mode, the 1.16 rollback build keeps its original classes.

If you generated the chat UI, its model picker should use `RubyLLM.models`, and tool calls are a hash: iterate them with `message.tool_calls.each_value`. You can regenerate with `bin/rails generate ruby_llm:chat_ui --force`, but read what it overwrites first.

## Your Own Data

Most apps can skip this section. Read it if you added things to RubyLLM's records.

If you put product settings on the old model table (defaults, availability flags, price overrides), move them to a table you own, keyed by provider and model ID. The extra columns survive, but RubyLLM won't maintain them.

The backfill creates one usage entry per historical response with recorded usage, and keeps any costs you stored. It can't recover retries or prices 1.16 never recorded. Compare totals with your own accounting before you change any of it, and keep customer billing, credits, and quotas in your app. RubyLLM tracks what providers charged you, not what you charge your customers.

Check your own foreign keys, logs, and evaluations that point at the old model and tool-call tables too.

## Going Back, in Copy Mode

Before switching versions, finish pending tool calls and approvals, and finish or cancel pending batches. Stop affected traffic and workers. Then, from the 2.0 app:

```bash
bin/rails ruby_llm:upgrade:rollback
```

Deploy the 1.16 build and restart. Conversations that 2.0 touched stay in the database but are hidden from 1.16, so nothing written in the new format gets mangled by the old code. Everything else keeps working.

To return to 2.0, stop traffic again and run, from the 2.0 app:

```bash
bin/rails ruby_llm:upgrade:resume
```

Resume brings over what 1.16 wrote in the meantime and unhides the 2.0 conversations. Wait for it to succeed before reopening. Neither task restarts provider jobs or undoes what tools already did in the outside world.

One database runs one version at a time, so you can't use this to run 1.16 and 2.0 side by side as a canary.

## Clean Up Later

Once 2.0 has run in production long enough that you trust it, generate cleanup with the same mappings, and deploy it in a later release.

Rename:

```bash
bin/rails generate ruby_llm:upgrade --phase cleanup
bin/rails db:migrate
```

Copy, with affected processes stopped, closes the way back first:

```bash
bin/rails ruby_llm:upgrade:finalize
bin/rails generate ruby_llm:upgrade --mode copy --phase cleanup
bin/rails db:migrate
```

Cleanup drops the legacy message columns, `content_raw`, the old token and cost columns, and the progress table. Copy cleanup also drops the original model and tool-call tables, so move any references of your own first, then remove the generated `ruby_llm_upgrade.rb` concern and initializer. 2.0 never updates the legacy columns, so they only get staler from here.

After cleanup has run in every environment, delete the 2.0 upgrade migrations from `db/migrate`. They load helpers that only ship with 2.0, and your schema already records what they did.

## If Something Fails

The migrations have no `down`. A failed phase can be retried once you fix the cause. Copy mode has the rollback and resume tasks above. Abandoning a rename upgrade means restoring the database and the 1.16 build together, which also loses any writes made after the backup, so plan for that.

Changing the gem version back does not roll back the database.

The [complete 2.0 upgrade guide](https://github.com/crmne/ruby_llm/blob/v2.0.0/docs/_reference/upgrading.md) has every rename and every operational detail. Once you're through, your app has two fewer models to maintain, and everything in [What's New in 2.0](https://rubyllm.com/whats-new-in-2-0/) works with the chats and messages you already have.
