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
RubyLLM 2.0 is out (two and a half weeks ago, I've been busy). Agents that wait for a human and survive restarts. Video, speech, OCR, rerank. Provider tools with citations. A cost ledger that counts every attempt. Seventeen providers. [link]

LinkedIn:
RubyLLM 2.0 came out on September 18. This is the announcement, two and a half weeks late, because I was too busy shipping to write about shipping.

The headline: an agent can now ask to do something risky, like issue a refund, and wait. Declare `requires_approval` on the tool, and the call is saved in your database. A person approves it tomorrow, from another process, and the agent continues where it left off.

2.0 also adds video, speech, OCR, reranking and multimodal embeddings as plain Ruby calls. Provider-hosted tools like web search come back with typed citations. Usage is tracked per provider attempt, so retries and fallbacks show up in your costs instead of disappearing.

Across forty shared features and seventeen providers, built-in support went from 170 provider-feature pairs to 395.

`bundle add ruby_llm`, and the full tour is in the post.

[link]

## rubyllm-2-0-requires-approval

X:
My favorite thing in RubyLLM 2.0 is one line: requires_approval. The model asks to refund order 42, the call waits in your database, a human clicks yes, a job picks it up. Survives restarts and deploys. No thread waits on a human. [link]

LinkedIn:
I want my support agent to look up orders on its own. Refunds are a different story.

RubyLLM 2.0 adds requires_approval. Put it on a tool and the agent pauses before that call, shows you the exact arguments, and waits for approve or deny.

The part I care about: in Rails the call and the decision are database rows. The job finishes, the user takes their time, you deploy twice, and the next job picks up exactly where it stopped.

An approval is data, not a blocked thread. That's what makes it something you can trust near a payment provider.

[link]

## rubyllm-2-0-upgrading

X:
Upgrading a Rails app from RubyLLM 1.16 to 2.0? Phased migrations you can retry, nothing deleted until you say so, and an optional copy mode that keeps a route back to 1.16. The whole path, step by step: [link]

LinkedIn:
Major version upgrades are the posts people read nervously. So here's the RubyLLM 2.0 one, written to be read that way.

Your chats and messages keep their IDs. Every migration phase can be retried. The old columns stay until you run cleanup, in a later deploy, once you trust the result.

You choose between two modes. Rename is fast and simple, with a short maintenance window. Copy prepares and backfills while 1.16 keeps serving, pauses only for the final step, and keeps a route back to 1.16 until you close it. On a million-message benchmark: 20 seconds of downtime for rename, 4 for copy.

Most code changes are renames. The post has the table.

One practical note: do this upgrade on the 2.0 series. Finish it, cleanup included, before moving to the next release.

[link]

## rubyllm-2-0-new-verbs

X:
RubyLLM.animate("A red panda typing on a mechanical keyboard").save("panda.mp4")

That's a video. RubyLLM 2.0 also adds ocr, rerank, tokenize and count_tokens. One method per job, typed results. [link]

LinkedIn:
RubyLLM has always named methods after what you get back: chat, paint, embed. 2.0 adds five more.

animate makes video across Gemini, xAI, Bedrock, Azure and others. ocr turns PDFs into per-page markdown. rerank sorts your retrieval candidates by relevance. tokenize and count_tokens tell you how big a request is before you send it.

These are the jobs that used to send me looking for a second SDK. Now they sit next to the chat code and look like it.

Yes, there's a red panda.

[link]

## rubyllm-2-0-server-tools (title: Provider Tools)

X:
RubyLLM 2.0: with_provider_tools(:web_search). The provider runs the search, you get the answer and typed citations. Same alias on Anthropic, OpenAI, Gemini and more. Code execution and remote MCP too, with approvals on OpenAI. [link]

LinkedIn:
Your research assistant needs web search. You could integrate a search API, or use the one the model's provider already runs.

RubyLLM 2.0's with_provider_tools enables web search, code execution, file search, and remote MCP servers that run on the provider's side, next to your own Ruby tools.

The aliases are portable across providers. New provider tools work on day one with a raw definition, no gem release needed. Remote MCP calls on OpenAI can go through the same human approval flow as your own tools.

[link]

## rubyllm-2-0-citations

X:
"The contract allows termination with 30 days' notice." Says who? Which page? RubyLLM 2.0 turns every provider's citation format into one Citation object: source, quoted passage, page, position in the answer. [link]

LinkedIn:
Every LLM provider invented its own citation format: Anthropic blocks, Gemini grounding metadata, OpenAI annotations. Build footnotes directly against them and you build them once per provider.

RubyLLM 2.0 normalizes all of them into RubyLLM::Citation. Turn on with_citations for documents, return SearchResults from your RAG tools, or enable web search, and read response.citations either way.

Citations stream, persist in Rails, and Gemini's byte offsets become character offsets so footnotes land in the right place.

Models still get things wrong. With citations, your users can check.

[link]

## rubyllm-2-0-cost-and-usage-tracking

X:
RubyLLM 2.0 counts every provider attempt, not just messages. Retries, fallbacks, and cancelled streams all show up in chat.cost.total. And if a cost can't be known, it's nil, not $0.00. [link]

LinkedIn:
Your LLM provider bills you for requests. Most apps count messages.

Those stop matching the moment you add retries, fallbacks, or a stop button. RubyLLM 2.0 records every provider attempt, so `response.cost` and `chat.cost` include the work that never became a message.

When usage or pricing is unknown, the total is `nil`. A missing price never looks like a free request.

In Rails, attempts go to their own table with costs frozen at completion, ready for SQL reports and metrics.

[link]

## rubyllm-2-0-fallbacks-and-cancellation

X:
"Switch models and redeploy" is not an incident plan. RubyLLM 2.0: with_fallbacks("gpt-5.6", "gemini-3.7-flash"). Plus a Rails stop button that halts a streaming background job through the chat record, and rescue_from on agents. [link]

LinkedIn:
Providers go down at the worst possible moment.

RubyLLM 2.0 lets a chat or agent declare backup models. On a rate limit, overload, timeout or dropped connection, the same request moves to the next model, on any provider, and the chat goes back afterwards.

In Rails, the stop button works across processes. The controller flags the chat record, and the streaming job notices, stops, and cleans up. No Redis, no pub/sub.

Agents can declare their error policy with rescue_from, the same way Rails controllers do.

[link]

## rubyllm-2-0-prompt-caching

X:
Your agent resends the same system prompt, tools, and document every turn. RubyLLM 2.0: chat.with_caching, mark the stable part with cache_until_here, and check response.tokens.cache_read to see what you saved. [link]

LinkedIn:
By turn twenty, an agent has paid for the same 40-page contract twenty times.

Prompt caching fixes that, but every provider spells it differently: cache_control blocks, cache points, cache keys, cache resources. RubyLLM 2.0 puts it behind one method, `with_caching`.

Mark exactly where your stable prefix ends with `cache_until_here`. In Rails, that boundary persists with the conversation. Gemini and Vertex AI cache resources get a small lifecycle API too.

Cache reads and writes have their own token and cost buckets, so you can check whether caching paid off.

[link]

## rubyllm-2-0-batches

X:
Work that can wait shouldn't cost full price. RubyLLM 2.0: stage chats with ask_later, submit with RubyLLM.batch(chats), collect from any process with Batch.find. Same chat API, batch rates, Rails persistence included. [link]

LinkedIn:
Every major LLM provider charges less for work you're willing to wait for. Most apps don't use it, because every batch API has its own file format and polling ritual.

In RubyLLM 2.0 it's the chat API you already know. `ask_later` stages a question, `RubyLLM.batch` submits them all, and `Batch.find` collects them from any process.

In Rails, answers save through the same callbacks as a normal `ask`. Tool turns run locally between batches, and embeddings batch too.

Costs are priced at batch rates, and unknown prices stay unknown.

[link]

## rubyllm-2-0-files-and-attachments

X:
Five questions about the same 40 MB PDF shouldn't mean uploading it five times. RubyLLM 2.0: RubyLLM.upload once, pass it to with: forever. Large attachments upload themselves, and tools can return files. [link]

LinkedIn:
RubyLLM 2.0 gives files one API: upload, find, download, across twelve providers.

Most of the time you won't call it. Attach a big file like always and RubyLLM moves it to provider storage and sends a reference instead.

Tools can now return files too. A chart tool returns the chart, a browser tool returns the screenshot, and the model actually looks at it.

Write the return value once; RubyLLM translates it for each provider.

[link]

## rubyllm-2-0-text-to-speech

X:
RubyLLM could already listen. In 2.0 it talks back: RubyLLM.speak("Hello!").save("hello.mp3"). Voices, formats, streamed audio, plus streaming transcription with speaker labels. [link]

LinkedIn:
RubyLLM 2.0 adds RubyLLM.speak. You get a Speech object back with save and to_blob, so a Rails controller can answer with audio in one line.

OpenAI, Gemini, ElevenLabs, Deepgram, Mistral, xAI and more sit behind the same method. Voices and style controls stay in each provider's own vocabulary, because a lowest-common-denominator "emotion" option would do half of what each one can.

Transcription grew up too: transcripts stream as they're produced, and speaker labels work across providers.

Listen, answer, speak, with one library.

[link]

## rubyllm-2-0-own-the-transcript

X:
RubyLLM 2.0: chat.messages = whatever_the_model_should_see. Summarize, redact, trim. Plus provider compaction, chat.render to inspect the exact payload without calling the model, and finish reasons that mean the same thing on every provider. [link]

LinkedIn:
The history your users keep and the history your model needs are not the same thing.

RubyLLM 2.0 lets you rewrite what the model sees with one setter, or give Rails a separate association for the model's transcript.

When a conversation gets long, ask the provider to compact it, automatically or on demand, while your app keeps every original message.

chat.render shows the exact request without sending it, and finish reasons are normalized, so "why was this cut off?" is one check on every provider.

[link]

## rubyllm-2-0-rails-table-ownership

X:
In RubyLLM 2.0 your Rails app has two models: Chat and Message. The registry, tool calls, usage, and batches live in tables RubyLLM owns, like Active Storage does with blobs. Less code in your app, and I can add features without asking you to edit classes you never wrote. [link]

LinkedIn:
A fresh RubyLLM 1.x install put four models in your Rails app: Chat, Message, Model, and ToolCall.

In 2.0 it's two. Your app owns the conversations, which is where users, permissions, and retention belong. RubyLLM owns its model registry, tool calls, usage, and batches in its own tables, the same way Active Storage owns its blobs.

Usage also moved off your messages and into one row per provider attempt, so retries and cancelled streams finally show up in `chat.cost.total`.

The upgrade from 1.16 is a generated set of migrations, with an optional copy mode if you want a way back.

[link]

## rubyllm-2-0-prompt-templates

X:
RubyLLM 2.0: prompts live in app/prompts. RubyLLM.render_prompt("support/instructions", name: user.name) renders ERB and returns a String. Agents find their own instructions file by convention, and Rails engines can ship prompts the host app overrides. [link]

LinkedIn:
Nobody wants to edit a two-page prompt inside a Ruby heredoc.

RubyLLM 2.0 gives prompts the same deal Rails gives views: put an ERB file in app/prompts, call `RubyLLM.render_prompt`, get a String. You can test it without an API key.

Named agents now pick up their instructions file automatically. `sync_instructions` updates existing conversations when the wording changes. Rails engines can ship prompts that the host app overrides by path.

Thanks to @kryzhovnik for extracting the renderer and @adrianthedev for asking for engine support.

[link]

## rubyllm-2-0-workflows-and-instrumentation

X:
Every AI framework grows a graph DSL eventually. RubyLLM 2.0 doesn't. RubyLLM.workflow and workflow.step just tag every model call, tool call, and usage event inside the block, so your logs can tell which task each request belonged to. Control flow stays Ruby. [link]

LinkedIn:
A sequence is method calls. A branch is a case. A loop is a loop. What Ruby developers lack isn't a way to express AI workflows, it's a way to see them afterwards.

RubyLLM 2.0 adds `RubyLLM.workflow` and `workflow.step`. Wrap the code you already have, and every model call, tool call, and usage event inside carries the workflow and step IDs.

Instrumentation grew from five events in 1.16 to twenty, delivered through ActiveSupport::Notifications in Rails. Group `usage.ruby_llm` by workflow ID and you get the real cost of a task, retries included.

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
RubyLLM 2.0 shipped three weeks ago. I just released 2.1 on stage at Deccan Queen on Rails: an MCP client where you decide what the model sees, typed judgments, evaluations for your agents, tool progress, OpenTelemetry, and a lot less overhead per call. [link]

LinkedIn:
RubyLLM 2.1 is out, three weeks after 2.0. I released it on stage at Deccan Queen on Rails in Pune today.

It brings an MCP client designed the way I think MCP should be used: you describe a server in a Ruby class, keep only the tools you need, rename them, fix the arguments the model shouldn't choose, and require approval where it matters.

It also adds typed judgments (probabilities, choices, and scores instead of parsing "Yes." out of a sentence) and evaluations that tell you whether your agent's answers got better or worse after a change.

Tools can report progress while they run, one line turns on OpenTelemetry tracing without exporting prompts, and Hetzner joins as provider number nineteen.

And it's faster without code changes: a streamed 40-turn chat with an image now keeps 0.48 MB in memory instead of 28 MB.

[link]

## rubyllm-2-1-mcp

X:
In April I wrote "Use MCP to prototype. Then replace it with crafted tools you actually control." RubyLLM 2.1 ships an MCP client built on that advice: servers are Ruby classes, only picks the tools, you rewrite their names and descriptions, pin arguments, and approve calls. [link]

LinkedIn:
In April I called MCP the biggest offender in bloated agent context windows. Today RubyLLM 2.1 ships an MCP client. I'm aware.

The problem was never the protocol. It's that clients hand the model every tool a server has, with descriptions you didn't write and never read.

So in RubyLLM, a server is a Ruby class you own. You pick which tools the model sees, rename and redescribe them, fix the arguments it shouldn't choose, filter results through your own method, and require approval before anything destructive runs. Every server tool is also a Ruby method you can call from the console.

Approvals and a server's questions pause the chat and survive restarts in Rails. Under the hood: OAuth per the MCP spec, client credentials, workload identity, enterprise SSO, DPoP, and the official conformance suite in CI.

Prototype with MCP, then craft your tools. Now both happen in the same class.

[link]

## rubyllm-2-1-judgments-and-evaluations

X:
"How do you know your agent works?" "I tried it and it seemed fine." RubyLLM 2.1 fixes that: typed judgments (probabilities, choices, scores your code can branch on) and evaluations you run with bin/rails "ruby_llm:eval[SupportEvaluation]". [link]

LinkedIn:
Ask anyone shipping an AI agent how they know it works. Usually the answer is "I tried it and it seemed fine."

RubyLLM 2.1 is out, and it takes that question on from two sides.

Judgments turn fuzzy questions like "is this urgent?" or "which team owns this?" into typed answers: probabilities, choices with full distributions, and scores. The model answers the question, and your code decides what to do with it.

Evaluations turn "seemed fine" into a number. You write a Ruby class that runs your agent and a YAML file of cases with reference answers, then run one command. A model checks each answer, Ruby assertions check what the agent actually did, and the report shows every verdict, its reason, and what the run cost.

It also runs as RSpec or Minitest, works in CI, and can show live progress in your own app.

[link]

## rubyllm-2-1-faster

X:
RubyLLM 2.0 took 116 ms to stream one 2 MB event. 2.1 takes 2 ms. The old parser rescanned a split line on every network read. Here's that and the other things that got faster, plus a benchmark task you can run without API keys. [link]

LinkedIn:
"The model takes three seconds, who cares about library overhead?" That's true until something quadratic meets a real user's real image.

For RubyLLM 2.1 I took the providers out of the picture and measured what the library itself costs. Streaming a 2 MB event went from 116 ms to 2 ms. A streamed 40-turn chat with an image went from keeping 28 MB to 0.48 MB, because every reply was quietly holding a copy of the whole conversation.

Calls now share HTTP connections too. With a keep-alive adapter, twenty calls make one TLS handshake instead of twenty.

The post walks through why each one was slow. You can reproduce every number with `rake benchmark:compare`, no API keys needed.

[link]

## rubyllm-2-1-opentelemetry

X:
RubyLLM 2.1: RubyLLM::OpenTelemetry.enable and every model call, tool, and workflow is a span in your tracing backend. GenAI semantic conventions, your own SDK and exporters. It exports metadata only, never prompts or responses. [link]

LinkedIn:
RubyLLM 2.1 adds OpenTelemetry tracing with one line: RubyLLM::OpenTelemetry.enable.

Every model call, tool run, and workflow becomes a span that follows the OpenTelemetry GenAI semantic conventions. Spans nest under your existing traces, so the HTTP call inside a tool shows up under the tool that made it.

RubyLLM uses the SDK and exporters your app already configures. It never starts, flushes, or shuts them down, and if tracing fails, your call carries on.

The part I care about most: it exports metadata only. Models, token counts, finish reasons, tool names. It never exports prompts, responses, tool arguments, or exception messages. Your users trusted your app with their words, not your tracing vendor.

[link]
