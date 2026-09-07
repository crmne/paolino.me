---
layout: post
title: "Upgrading a Rails App to RubyLLM 2.0"
description: "Upgrade from RubyLLM 1.16 in phases, choose rename or copy mode, and remove legacy data only after checking the conversion."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

RubyLLM 2.0 has a database migration as well as API changes. I've put a lot of work into the upgrade path, including making the backfill resumable and keeping the old message columns until you've checked the conversion.

Here's the path from a Rails app on 1.16.

## Start With a Working 1.16 App

If you're on an older version, work through the minor upgrades to 1.16 first. The 2.0 generator expects that schema; it doesn't guess how an older or customized schema should map.

Finish or cancel in-flight conversations and tool rounds. Take a database snapshot, then rehearse the exact 2.0 candidate on a recent copy of production data. Measure the migration duration and compare message counts, tool-result links, token buckets, and any costs your application already stores.

Update your Gemfile to the 2.0 version you're testing, then generate the migrations:

```bash
bundle update ruby_llm
bin/rails generate ruby_llm:upgrade
```

If your models have custom names, pass all the mappings that differ from the defaults:

```bash
bin/rails generate ruby_llm:upgrade \
  chat:AI::Chat \
  message:AI::Chat::Message \
  model:AI::LLMModel \
  tool_call:AI::Chat::ToolCall
```

The generator prints the classes and tables it resolved. Read those and the migration files before running them.

## Choose Rename or Copy Mode

The default mode renames the model and tool-call tables in place. It uses less storage and avoids copying those supporting tables. Returning to 1.16 means restoring the matching database recovery point and application version.

For a controlled route back to 1.16, choose copy mode instead when generating:

```bash
bin/rails generate ruby_llm:upgrade --mode copy
```

It preserves the old supporting tables and chat model reference alongside the 2.0 replacements. It also generates `app/models/concerns/ruby_llm_upgrade.rb` and `config/initializers/ruby_llm_upgrade.rb`. Put both files in the 2.0 app and the 1.16 build you would deploy for rollback. That older build keeps its original `Model`, `ToolCall`, and `acts_as` declarations.

Copy mode doesn't dual-write transcripts. When 2.0 writes to a conversation, it marks the whole conversation as version 2. During rollback, 1.16 hides that conversation and prevents ordinary record writes to it. The data remains stored and becomes available again when you return to 2.0. Untouched conversations remain usable in 1.16.

That is a useful tradeoff when you can accept some conversations being unavailable during rollback. It needs extra disk space and copy time, and its short shared write lock can reduce throughput during the compatibility window. Rehearse with both builds and your own data.

## Three Phases, Then Cleanup Later

The default command writes three migrations:

| Phase | What it does |
|---|---|
| Prepare | Checks the 1.16 schema, renames or copies supporting tables, and adds the 2.0 fields and indexes. |
| Backfill | Converts message content, tool-result links, and historical usage. |
| Finish | Verifies the conversion, enforces constraints, and records that the upgrade finished. |

Legacy message columns remain for comparison and recovery evidence. Cleanup is a fourth phase you generate separately in a later deployment.

This is a maintenance-window upgrade. Stop affected web requests, workers, scheduled jobs, and retries before preparation. Keep them stopped through backfill, finish, and any application-specific data conversions. Neither the old app nor the new one can operate normally against a partly migrated schema.

Once those processes are stopped:

```bash
bin/rails db:migrate
bin/rails ruby_llm:load_models
```

`load_models` imports the packaged registry without network access. You can fetch newer metadata later with `RubyLLM.models.refresh`.

Rename mode commits 10,000-message batches together with their checkpoints. If it's interrupted, retrying resumes without duplicating historical usage. Copy mode rebuilds the records derived from 1.16 so edits and deletions made during a rollback are reconciled correctly. For deployments with a short release-phase timeout, generate individual phases with `--phase prepare`, `--phase backfill`, and `--phase finish`, and run their migration versions in order from an operator process during maintenance. Use the same model mappings and mode each time.

## Remove the Old Application Models

Your app keeps `Chat` and `Message`. RubyLLM owns the registry, tool calls, usage, and batches under the `ruby_llm_` table prefix.

In the 2.0 application, remove `Model` and `ToolCall` from `app/models`, along with `acts_as_model` and `acts_as_tool_call`. A copy-mode rollback build still needs its original 1.16 classes and declarations. Remove `config.model_registry_class` and `config.use_new_acts_as` from the initializer. Those configuration settings are temporarily ignored with warnings so older apps can boot for the generator.

Also remove obsolete options from the macros that remain. `acts_as_chat` accepts `messages:`, `message_class:`, and `messages_foreign_key:`. `acts_as_message` accepts `chat:`, `chat_class:`, `chat_foreign_key:`, and `touch_chat:`. Leftover `model:` or `tool_calls:` keywords raise on boot.

Don't drop the old supporting tables yourself: the upgrade either renamed them or retained them for copy-mode rollback.

## Update the Call Sites

Most public API changes are straightforward renames:

| Before | 2.0 |
|---|---|
| `with_tool(Weather)` | `with_tools(Weather)` |
| `with_tools(W, choice: :required)` | `with_tools(W).with_tool_options(choice: :required)` |
| Tool `desc`, `param`, `params` | `description`, `parameter`, `parameters` |
| `with_params`, `params:` | `with_provider_options`, `provider_options:` |
| `response.input_tokens`, `response.output_tokens` | `response.tokens.input`, `response.tokens.output` |
| `tokens.reasoning` | `tokens.thinking` |
| `response.model_id` | `response.model` |
| `response.content` as parsed JSON | `response.parsed`; `content` holds the JSON string |
| `RubyLLM::Schema` | `Schematist::Schema` |
| `model.supports_vision?` | `model.supports?(:vision)` |
| `RubyLLM::Model::Info` | `RubyLLM::Model` |
| `RubyLLM.models.find(id, :openai)` | `RubyLLM.models.find(id, provider: :openai)` |
| `RubyLLM.models.refresh!` | `RubyLLM.models.refresh` |
| `create_user_message` | `ask_later` or `add_message` |
| `on_new_message`, `on_end_message` | `before_message`, `after_message` |
| `on_tool_call`, `on_tool_result` | `before_tool_call`, `after_tool_result` |
| `tool.call({ city: "Berlin" })` | `tool.call(city: "Berlin")` |
| `halt`, `Tool::Halt` | Conditions in your loop, or tool approval when you need a decision |

For prerelease code, also check the bang methods: use `cancel`, `approve`, `deny`, `cache_until_here`, and `sync_instructions`. Explicit cache resources use `renew` and `delete`.

Finish reasons are normalized symbols: `:stop`, `:max_tokens`, `:tool_calls`, and `:content_filter`. Update comparisons against provider strings, or use `stopped?`, `max_tokens?`, `tool_call_stop?`, and `content_filtered?`.

Feature switches use `false` to disable: `with_thinking(false)`, `with_caching(false)`, `with_citations(false)`, and `with_compaction(false)`. They reject `nil`. Value setters such as `with_temperature` and `with_max_output_tokens` still use `nil` to clear their setting.

Check RubyLLM call sites individually when changing `params:`. Rails controller parameters have nothing to do with this rename.

## Check Your App's Own Extensions

Generated chat UIs need updated model lists and tool-call rendering. Use `RubyLLM.models` for the registry and `message.tool_calls.each_value` for the hash of tool calls. If you've customized the UI, review those changes before regenerating files.

If you added defaults, availability flags, or other product settings to the old model table, move them to an application table keyed by model ID and provider. The upgrade retains extra columns but RubyLLM doesn't maintain them. Audit your own logs, evaluations, approvals, and foreign keys too.

Copy-mode guards cover ordinary Active Record reads, saves, updates, and destroys. They cannot protect callback-bypassing operations such as `update_columns`, direct deletes, bulk SQL, or attachment purges. Custom references to model or tool-call rows, accounting tables, and approval workflows need application-specific conversion and rollback tests. Copying columns alone does not make an arbitrary application compatible with both versions.

The backfill creates one succeeded usage entry per historical assistant response or other message with recorded usage. It preserves available counts and supported custom cost fields. It cannot recover retry history or costs that 1.x never stored.

Compare the new rows with your pre-upgrade baseline before deleting your own accounting. Keep customer credits, quotas, and billing adjustments where they belong in your application; RubyLLM tracks provider usage.

## Switch Versions in Copy Mode

Finish pending tool calls and approvals, and finish or cancel pending batches. Stop affected traffic and workers. From the 2.0 application, run:

```bash
bin/rails ruby_llm:upgrade:rollback
```

Then deploy the prepared 1.16 build before restarting traffic. Do not run mixed 1.16 and 2.0 writers.

To return to 2.0, stop affected traffic and workers again. From the 2.0 application:

```bash
bin/rails ruby_llm:upgrade:resume
```

Resume reconciles the conversations used by 1.16 and their derived records before enabling 2.0 writes. Wait for it to succeed before reopening the app. The conversations previously changed by 2.0 become available again. These tasks don't restart provider jobs or undo external actions performed by tools.

## Cleanup After Verification

After checking the upgraded app and data, generate cleanup with the same model mappings. In rename mode:

```bash
bin/rails generate ruby_llm:upgrade --phase cleanup
bin/rails db:migrate
```

For copy mode, close the rollback window first, with affected traffic and workers stopped:

```bash
bin/rails ruby_llm:upgrade:finalize
bin/rails generate ruby_llm:upgrade --mode copy --phase cleanup
bin/rails db:migrate
```

Cleanup checks that finish succeeded, then removes the legacy message references, `content_raw`, token and supported cost columns, and the temporary checkpoint table. Copy cleanup also removes the old supporting tables and conversation marker, so move your own references first. After it succeeds, remove the generated compatibility concern and initializer from the 2.0 app. A small finalized-state record remains to prevent an old guarded build from writing.

Until cleanup, remember that 2.0 doesn't keep those old columns synchronized with new messages.

The migrations have no `down` path. Retry a failed phase after fixing its cause. Copy mode provides the explicit rollback and resume tasks above; rename mode requires restoring the previous database and application together. Finalization closes the copy-mode rollback window, and cleanup removes the retained legacy data. Changing the gem version alone is not a database rollback.

The [complete upgrade guide](https://rubyllm.com/next/upgrading/) has the remaining API changes and production migration details. Once this is done, your app has fewer RubyLLM models to maintain, and the new features work through the chats and messages you already have.
