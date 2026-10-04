---
published: false
---

# RubyLLM 2.0 and 2.1 launch kit

Schedule, plus X and LinkedIn copy for every post. Replace `[link]` with `https://paolino.me/<slug>/`.

Publishing mechanics: a post in `_posts/` with a future `date:` goes live on the first daily build after that date
(cron at 07:00 UTC in `.github/workflows/jekyll.yml`). SendFox only gets a draft campaign; nothing is mailed automatically.

## Schedule

Every post below is already in `_posts/` with its date. Review each one before its day; to move one, rename the file and
change its `date:`.

| Day | Post (slug) |
| --- | --- |
| Mon 5 Oct | `rubyllm-2-0` |
| Tue 6 Oct | `rubyllm-2-0-requires-approval` |
| Wed 7 Oct | `rubyllm-2-0-upgrading` (must be out before 2.1, which drops the 1.16 upgrade generator) |
| Thu 8 Oct, 14:40 IST | `rubyllm-2-1`, `rubyllm-2-1-mcp`, `rubyllm-2-1-judgments-and-evaluations`, `rubyllm-2-1-faster` |
| Fri 9 Oct | `rubyllm-2-0-new-verbs` |
| Mon 12 Oct | `rubyllm-2-1-opentelemetry` |
| Wed 14 Oct | `rubyllm-2-0-server-tools` |
| Fri 16 Oct | `rubyllm-2-0-citations` |
| Mon 19 Oct | `rubyllm-2-0-cost-and-usage-tracking` |
| Wed 21 Oct | `rubyllm-2-0-fallbacks-and-cancellation` |
| Fri 23 Oct | `rubyllm-2-0-prompt-caching` |
| Mon 26 Oct | `rubyllm-2-0-batches` |
| Wed 28 Oct | `rubyllm-2-0-files-and-attachments` |
| Fri 30 Oct | `rubyllm-2-0-text-to-speech` |
| Mon 2 Nov | `rubyllm-2-0-own-the-transcript` |
| Wed 4 Nov | `rubyllm-2-0-rails-table-ownership` |
| Fri 6 Nov | `rubyllm-2-0-prompt-templates` |
| Mon 9 Nov | `rubyllm-2-0-workflows-and-instrumentation` |

2.1 day (Deccan Queen on Rails, Pune, talk at 14:40 IST = 09:10 UTC): the four 2.1 posts are dated
`2026-10-08 14:40:00 +0530`, so the 07:00 UTC daily build skips them. After the gem and the 2.1 docs are live, run
`gh workflow run jekyll.yml` (or push anything) to publish them. Social posts for the three companions can spread over
Thu/Fri/Mon.

Week of 5 Oct also has the kamal-backup 1.1 announcement (Tue or Wed afternoon CEST, see `kamal-backup-1-1-announcements.md`).

After 2.1 ships: the published agentic-loop post says `step until chat.complete? || chat.awaiting_approval?`. In 2.1
the documented stop condition is `|| chat.waiting?` (MCP input requests and tasks also pause). Add a one-line note.

---

# 2.0

## rubyllm-2-0

X:
RubyLLM 2.0 is out. Agents can wait for a human before a risky tool call and resume after restarts. It also adds video, speech, OCR, reranking, provider tools with citations, a cost ledger that counts every attempt, and seventeen providers. [link]

LinkedIn:
RubyLLM 2.0 is out, and it's the biggest release since 1.0.

An agent can now ask to do something risky, like issue a refund, and wait. Declare `requires_approval` on the tool and the call is saved in your database. A person can approve it later, from another process, and the agent continues where it left off.

2.0 also adds video, speech, OCR, reranking, and multimodal embeddings as plain Ruby calls. Provider-hosted tools like web search come back with typed citations. Usage is tracked per provider attempt, so retries and fallbacks show up in your costs.

Across forty shared features and seventeen providers, built-in support went from 170 provider-feature pairs to 395. Install it with `bundle add ruby_llm`. The post covers the rest.

[link]

## rubyllm-2-0-requires-approval

X:
RubyLLM 2.0 adds requires_approval for tools. The model asks to refund order 42, the call is saved with its arguments, a human approves or denies it, and a job continues from there. In Rails it survives restarts and deploys. [link]

LinkedIn:
A support agent can look up orders on its own. Refunds should wait for a person to approve them.

RubyLLM 2.0 adds requires_approval. Put it on a tool and the chat stops before that call, exposes the exact name and arguments, and waits for approve or deny. A denied call never runs, and the model is told it was denied.

In Rails, the call and the decision are database rows. The job that hit the approval finishes, the user answers whenever they get to it, and the next job continues with the same call, even after a deploy.

Pass tool_call.id to your payment provider as an idempotency key, so a call that is retried after a crash still refunds once.

[link]

## rubyllm-2-0-upgrading

X:
Upgrading a Rails app from RubyLLM 1.16 to 2.0: phased migrations you can retry, legacy data kept until you run cleanup, and an optional copy mode with a way back to 1.16. The full path, with the rename table: [link]

LinkedIn:
RubyLLM 2.0 changes the API and the Rails schema. This post walks through the upgrade from 1.16.

Your chats and messages keep their IDs. Every migration phase can be retried. The old columns stay until you run cleanup in a later deploy, after you've checked the result.

There are two modes. Rename is fast and simple, with AI paused for the whole migration. Copy prepares and backfills while 1.16 keeps serving, pauses only for the final phase, and keeps a way back to 1.16 until you finalize. On a benchmark with a million messages, rename paused AI for 20 seconds and copy for 4.

Most code changes are renames, and the post has the table. Do the upgrade on the 2.0 series and finish it, cleanup included, before moving to the next release.

[link]

## rubyllm-2-0-new-verbs

X:
RubyLLM.animate("A red panda typing on a mechanical keyboard").save("panda.mp4")

RubyLLM 2.0 adds animate, ocr, rerank, tokenize, and count_tokens. One method per job, each returning a typed result. [link]

LinkedIn:
RubyLLM names its methods after what you get back: chat, paint, embed. 2.0 adds five more.

animate generates video on Gemini, xAI, Bedrock, Azure, and others. ocr turns PDFs and images into markdown per page. rerank sorts retrieval candidates by relevance to a query. tokenize and count_tokens tell you how big a request is before you send it.

These are the jobs that used to send me looking for another SDK. Now they sit next to the chat code and follow the same conventions.

[link]

## rubyllm-2-0-server-tools (title: Provider Tools)

X:
RubyLLM 2.0: with_provider_tools(:web_search). The provider runs the search and you get the answer with citations. The same alias works on Anthropic, OpenAI, Gemini, and more. Code execution and remote MCP too, with approvals on OpenAI. [link]

LinkedIn:
If your assistant needs web search, you can integrate a search API yourself or use the one the model's provider already runs.

RubyLLM 2.0's with_provider_tools enables web search, code execution, file search, remote MCP servers, and more on the provider's side, next to your own Ruby tools.

The aliases work across providers. For a tool RubyLLM doesn't have an alias for yet, you can pass the provider's raw definition. Remote MCP calls on OpenAI and Azure can go through the same approval flow as your own tools.

[link]

## rubyllm-2-0-citations

X:
RubyLLM 2.0 turns citations from Anthropic, Gemini, OpenAI, Perplexity, and others into one Citation object: source, quoted passage, PDF page, and position in the answer. Works for documents, web search, and your own RAG tools. [link]

LinkedIn:
Every LLM provider has its own citation format: Anthropic citation blocks, Gemini grounding metadata, OpenAI annotations. If you build footnotes against each one, you build them once per provider.

RubyLLM 2.0 converts all of them into RubyLLM::Citation. Turn on with_citations for documents, return SearchResults from your RAG tools, or enable web search, and read response.citations in every case.

Citations arrive while streaming, persist in Rails, and Gemini's byte offsets are converted to character offsets so footnotes land in the right place.

Models still make mistakes, and citations let your users check the answer against its source.

[link]

## rubyllm-2-0-cost-and-usage-tracking

X:
RubyLLM 2.0 records usage for every provider attempt, so retries, fallbacks, and cancelled streams all count in chat.cost.total. When a cost can't be established, the total is nil instead of $0.00. [link]

LinkedIn:
Your LLM provider bills you for every request it ran. Most apps count messages instead.

The two numbers diverge once you add retries, fallbacks, or a stop button. RubyLLM 2.0 records every provider attempt, so response.cost and chat.cost include work that never became a message.

When usage or pricing is unknown, the total is nil, so an unpriced model never shows up as free.

In Rails, attempts are written to their own table with costs frozen when each attempt finishes, ready for SQL reports and metrics.

[link]

## rubyllm-2-0-fallbacks-and-cancellation

X:
RubyLLM 2.0 adds with_fallbacks("gpt-5.6", "gemini-3.7-flash"): when a provider fails, the same request moves to the next model. Also: a Rails stop button that halts a streaming background job through the chat record, and rescue_from on agents. [link]

LinkedIn:
Providers go down, and switching models and redeploying is a slow way to respond.

RubyLLM 2.0 lets a chat or agent declare backup models. On a rate limit, overload, timeout, or dropped connection, the same request moves to the next model, on any provider, and the chat returns to its own model afterwards.

In Rails, the stop button works across processes. The controller flags the chat record, and the streaming job notices, stops, and cleans up, without Redis or pub/sub.

Agents can declare their error policy with rescue_from, the same way Rails controllers do.

[link]

## rubyllm-2-0-prompt-caching

X:
An agent resends the same system prompt, tools, and documents on every turn. RubyLLM 2.0 adds chat.with_caching, cache_until_here to mark where the stable part ends, and response.tokens.cache_read to see what was reused. [link]

LinkedIn:
By turn twenty, an agent has sent the same 40-page contract twenty times, and paid for it each time.

Prompt caching lets providers bill that repeated prefix at a fraction of the input price, but every provider configures it differently: cache_control blocks, cache points, cache keys, cache resources. RubyLLM 2.0 puts it behind one method, with_caching.

cache_until_here marks where your stable prefix ends, and in Rails that boundary is stored with the conversation. Gemini and Vertex AI cache resources get a small lifecycle API.

Cache reads and writes have their own token and cost buckets, so you can check whether caching paid off.

[link]

## rubyllm-2-0-batches

X:
Most LLM providers charge less for work that can wait. RubyLLM 2.0 stages chats with ask_later, submits them with RubyLLM.batch(chats), and collects the answers from any process with Batch.find, saving them to Rails if you use it. [link]

LinkedIn:
Most LLM providers charge less for work you're willing to wait for. Few apps use it, because every batch API has its own file format and its own steps for uploading, polling, and matching results.

In RubyLLM 2.0 you use the chat API you already know. ask_later stages a question, RubyLLM.batch submits them all, and Batch.find collects the answers from any process.

In Rails, answers are saved through the same callbacks as a normal ask. Tool turns run locally between batches, and embeddings can be batched too.

Costs are priced at batch rates, and unknown prices stay nil instead of turning into zero.

[link]

## rubyllm-2-0-files-and-attachments

X:
RubyLLM 2.0 has one file API: RubyLLM.upload a file once, then pass it to with: on any request. Large attachments move to provider storage automatically, and tools can return files the model can look at. [link]

LinkedIn:
RubyLLM 2.0 gives files one API across twelve providers: upload, find, and download.

Most of the time you won't call it. Attach a large file the usual way and RubyLLM uploads it to the provider and sends a reference instead, then reuses that upload for follow-up questions.

Tools can now return files too. A chart tool can return the chart and a browser tool a screenshot, and a vision model can look at them.

You write the return value once, and RubyLLM formats it the way each provider expects.

[link]

## rubyllm-2-0-text-to-speech

X:
RubyLLM 2.0 adds text to speech: RubyLLM.speak("Hello!").save("hello.mp3"). Choose a voice and format, stream the audio as it arrives, and pair it with streaming transcription that labels speakers. [link]

LinkedIn:
RubyLLM 2.0 adds RubyLLM.speak. It returns a Speech object with save and to_blob, so a Rails controller can answer with audio in one line.

OpenAI, Gemini, ElevenLabs, Deepgram, Mistral, xAI and more work through the same method. Voices and style options use each provider's own names, passed through provider_options, instead of a generic "emotion" setting that would cover only part of what each one supports.

Transcription also streams now, and speaker labels work across providers.

With both, a Ruby app can take a voice message, have a model answer it, and reply with audio, all through one library.

[link]

## rubyllm-2-0-own-the-transcript

X:
In RubyLLM 2.0 you can rewrite what the model sees with chat.messages =. There's also provider compaction, chat.render to inspect the exact payload without calling the model, and finish reasons normalized across providers. [link]

LinkedIn:
The history your users keep and the history your model needs often differ.

RubyLLM 2.0 lets you rewrite what the model sees with one setter, or give your Rails chat a separate association for the model's transcript.

When a conversation gets long, the provider can compact it, automatically or on demand, while your app keeps every original message.

chat.render shows the exact request without sending it, and finish reasons are normalized, so checking for a cut-off answer works the same way on every provider.

[link]

## rubyllm-2-0-rails-table-ownership

X:
In RubyLLM 2.0 your Rails app has two models: Chat and Message. The model registry, tool calls, usage, and batches live in tables RubyLLM owns, the way Active Storage owns its blobs. New features no longer mean editing classes in your app. [link]

LinkedIn:
A fresh RubyLLM 1.x install put four models in your Rails app: Chat, Message, Model, and ToolCall.

In 2.0 there are two. Your app owns the conversations, along with users, permissions, and retention. RubyLLM keeps its model registry, tool calls, usage, and batches in its own tables, the same way Active Storage keeps its blobs.

Usage moved off your messages into one row per provider attempt, so retries and cancelled streams are included in chat.cost.total.

The upgrade from 1.16 is a generated set of migrations, with an optional copy mode that keeps a rollback path.

[link]

## rubyllm-2-0-prompt-templates

X:
RubyLLM 2.0 puts prompts in app/prompts. RubyLLM.render_prompt("support/instructions", name: user.name) renders ERB and returns a String. Agents find their instructions file by convention, and Rails engines can ship prompts the host app overrides. [link]

LinkedIn:
Long prompts are hard to maintain inside Ruby heredocs.

RubyLLM 2.0 treats prompts the way Rails treats views: put an ERB file in app/prompts, call RubyLLM.render_prompt, and get a String back. You can test it without an API key.

Named agents pick up their instructions file automatically. sync_instructions updates existing conversations when the wording changes. Rails engines can ship prompts that the host app overrides by path.

Thanks to @kryzhovnik for extracting the renderer and @adrianthedev for asking for engine support.

[link]

## rubyllm-2-0-workflows-and-instrumentation

X:
RubyLLM 2.0 adds RubyLLM.workflow and workflow.step. They tag every model call, tool call, and usage event inside the block with the workflow and step, so your logs show which task each request belonged to. Your control flow stays plain Ruby. [link]

LinkedIn:
Ruby already has sequences, branches, loops, and retries. What's usually missing in an AI app is a way to see afterwards which model calls belonged to which task.

RubyLLM 2.0 adds RubyLLM.workflow and workflow.step. Wrap the code you already have, and every model call, tool call, and usage event inside carries the workflow and step IDs.

Instrumentation grew from five events in 1.16 to twenty, delivered through ActiveSupport::Notifications in Rails. Group usage.ruby_llm by workflow ID to get the cost of a task, retries included.

In 2.1, the same workflows export as OpenTelemetry spans.

[link]

## Coding assistant skill (no post, link the guide)

X:
RubyLLM ships a coding skill inside the gem, versioned with the code:

npx skills add "$(bundle show ruby_llm)" --skill rubyllm

Your assistant gets the API that matches your bundle instead of whatever it remembers from 1.x. https://rubyllm.com/ai-coding-assistants/

---

# 2.1

## rubyllm-2-1

X:
RubyLLM 2.1 is out. I released it on stage at Deccan Queen on Rails: an MCP client where you choose what the model sees, typed judgments, evaluations for your agents, tool progress, OpenTelemetry, and less overhead on every call. [link]

LinkedIn:
RubyLLM 2.1 is out. I released it on stage at Deccan Queen on Rails in Pune.

It adds an MCP client built the way I think MCP should be used. You describe a server in a Ruby class, keep only the tools you need, rename them, fix the arguments the model shouldn't choose, and require approval where it matters.

It also adds typed judgments (probabilities, choices, and scores instead of parsing "Yes." out of a sentence) and evaluations that show whether your agent's answers improved after a change.

Tools can report progress while they run, one line turns on OpenTelemetry tracing without exporting prompts, and Hetzner joins as provider number nineteen. A streamed 40-turn chat with an image now keeps 0.48 MB in memory instead of 28 MB, with no code changes.

[link]

## rubyllm-2-1-mcp

X:
I wrote "Use MCP to prototype. Then replace it with crafted tools you actually control." RubyLLM 2.1 has an MCP client built on that advice: a server is a Ruby class where you pick tools, rewrite descriptions, pin arguments, and require approval. [link]

LinkedIn:
In April I called MCP the biggest offender in bloated agent context windows. RubyLLM 2.1 now ships an MCP client, designed around that critique.

The trouble is what clients do with MCP: they hand the model every tool a server has, with descriptions you didn't write. In RubyLLM a server is a Ruby class you own. You pick which tools the model sees, rename and redescribe them, fix the arguments it shouldn't choose, filter results through your own method, and require approval before anything destructive runs.

Every server tool is also a Ruby method you can call from the console. Approvals and a server's questions pause the chat and survive restarts in Rails. OAuth follows the MCP spec, with client credentials, enterprise SSO, and DPoP, and the official conformance suite runs in CI.

Prototype with MCP, then craft your tools, in the same class.

[link]

## rubyllm-2-1-judgments-and-evaluations

X:
How do you know your agent works? RubyLLM 2.1 adds typed judgments (probabilities, choices, and scores your code can branch on) and evaluations you run with bin/rails "ruby_llm:eval[SupportEvaluation]", in CI or as RSpec and Minitest tests. [link]

LinkedIn:
Ask someone shipping an AI agent how they know it works, and the answer is often "I tried it and it seemed fine." RubyLLM 2.1 adds two tools for that question.

Judgments turn questions like "is this urgent?" or "which team owns this?" into typed answers: probabilities, choices with full distributions, and scores. The model answers, and your code decides what to do with the answer.

Evaluations turn "seemed fine" into a number. You write a Ruby class that runs your agent and a YAML file of cases with reference answers, then run one command. A model checks each answer, Ruby assertions check what the agent did, and the report shows every verdict, its reason, and what the run cost.

Evaluations also run as RSpec or Minitest tests, fail CI when a case fails, and can report live progress to your own app.

[link]

## rubyllm-2-1-faster

X:
RubyLLM 2.0 took 116 ms to stream one 2 MB event. 2.1 takes 2 ms, because the old parser rescanned a split line on every network read. The post covers that and the other speedups, with a benchmark task you can run without API keys. [link]

LinkedIn:
Library overhead is easy to dismiss when the model takes seconds to answer. It adds up once something quadratic meets a large input.

For RubyLLM 2.1 I took the providers out of the picture and measured what the library itself costs. Streaming a 2 MB event went from 116 ms to 2 ms. A streamed 40-turn chat with an image went from keeping 28 MB to 0.48 MB, because every reply was holding a copy of the conversation before it.

Calls now share HTTP connections too. With a keep-alive adapter, twenty calls make one TLS handshake instead of twenty.

The post explains why each one was slow. You can reproduce the numbers with `rake benchmark:compare`, no API keys needed.

[link]

## rubyllm-2-1-opentelemetry

X:
RubyLLM 2.1 adds OpenTelemetry tracing: RubyLLM::OpenTelemetry.enable and every model call, tool run, and workflow is a span in your tracing backend. It uses your SDK and exporters, and exports metadata only, never prompts or responses. [link]

LinkedIn:
RubyLLM 2.1 adds OpenTelemetry tracing with one line: RubyLLM::OpenTelemetry.enable.

Every model call, tool run, and workflow becomes a span following the OpenTelemetry GenAI semantic conventions. Spans join your existing traces, so the HTTP call a tool makes shows up under that tool.

RubyLLM uses the SDK and exporters your app already configures and never starts, flushes, or shuts them down. If tracing fails, RubyLLM logs a warning and the call carries on.

Spans carry metadata only: models, token counts, finish reasons, tool names. Prompts, responses, tool arguments, and exception messages are never exported, because traces usually go to a third party your users never agreed to share their words with.

[link]
