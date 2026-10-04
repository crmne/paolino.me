---
published: false
---

# RubyLLM 2.0 and 2.1 launch kit

One post per release. Send each one as the newsletter on its publishing day.

| When | Post |
| --- | --- |
| Mon 5 Oct, 09:00 CEST (daily build) | https://paolino.me/rubyllm-2-0/ |
| Thu 8 Oct, after the talk (14:40 IST) | https://paolino.me/rubyllm-2-1/ |

2.1 day: the post is dated `2026-10-08 14:40:00 +0530`, so the 07:00 UTC build skips it. Once the gem and the 2.1 docs are live, run `gh workflow run jekyll.yml` to publish it.

After 2.1 ships, the published agentic-loop post says `step until chat.complete? || chat.awaiting_approval?`; in 2.1 the documented stop condition is `|| chat.waiting?`. Add a one-line note.

Section posts are optional follow-ups for the days after each release. Each links a section of the long post. Check that the X ones stay under 280 characters after the URL change (a URL counts as 23).

---

# 2.0

## Release post

X:
RubyLLM 2.0 is out. Tools can wait for human approval across jobs and deploys. It also adds video, speech, OCR, reranking, provider tools with citations, a cost ledger that counts every attempt, batches, and seventeen providers. Everything in one post: https://paolino.me/rubyllm-2-0/

LinkedIn:
RubyLLM 2.0 is out, and it's the biggest release since 1.0.

It starts with tools that wait for a person. Mark a tool `requires_approval` and the agent stops before running it. In Rails the pending call is saved in your database, so someone can approve it later from another process, even after a deploy, and the agent continues from there.

The release also adds video generation, text to speech, OCR, reranking and token counting. Web search and other tools that providers run on their side now share one API with your own Ruby tools and return typed citations. A usage ledger records every provider attempt, including retries, fallbacks and cancelled streams, and reports an unknown cost as nil rather than zero. Batches, prompt caching, model fallbacks and seventeen providers are in too.

Rails apps now keep only Chat and Message. RubyLLM owns its registry, tool calls, usage and batches in its own tables, and the upgrade from 1.16 runs in phases, with a copy mode that keeps a way back.

The post walks through every feature, with code and links to the guides: https://paolino.me/rubyllm-2-0/

## Section posts

### #tool-approval-and-durable-agents

RubyLLM 2.0 adds requires_approval for tools. The model asks to refund order 42, the call is saved with its arguments, a human approves or denies it, and a job continues from there. In Rails it survives restarts and deploys. https://paolino.me/rubyllm-2-0/#tool-approval-and-durable-agents

### #new-operations

RubyLLM.animate("A red panda typing on a mechanical keyboard").save("panda.mp4")

RubyLLM 2.0 adds animate, ocr, rerank, tokenize, and count_tokens. One method per job, each returning a typed result. https://paolino.me/rubyllm-2-0/#new-operations

### #speech-and-transcription

RubyLLM 2.0 adds text to speech: RubyLLM.speak("Hello!").save("hello.mp3"). Choose a voice and format, stream the audio as it arrives, and pair it with streaming transcription that labels speakers. https://paolino.me/rubyllm-2-0/#speech-and-transcription

### #provider-tools

RubyLLM 2.0: with_provider_tools(:web_search). The provider runs the search and you get the answer with citations. The same alias works on Anthropic, OpenAI, Gemini, and more. Code execution and remote MCP too, with approvals on OpenAI. https://paolino.me/rubyllm-2-0/#provider-tools

### #citations

RubyLLM 2.0 turns citations from Anthropic, Gemini, OpenAI, Perplexity, and others into one Citation object: source, quoted passage, PDF page, and position in the answer. Works for documents, web search, and your own RAG tools. https://paolino.me/rubyllm-2-0/#citations

### #files-and-attachments

RubyLLM 2.0 has one file API: RubyLLM.upload a file once, then pass it to with: on any request. Large attachments move to provider storage automatically, and tools can return files the model can look at. https://paolino.me/rubyllm-2-0/#files-and-attachments

### #cost-and-usage

RubyLLM 2.0 records usage for every provider attempt, so retries, fallbacks, and cancelled streams all count in chat.cost.total. When a cost can't be established, the total is nil instead of $0.00. https://paolino.me/rubyllm-2-0/#cost-and-usage

### #fallbacks-cancellation-and-errors

RubyLLM 2.0 adds with_fallbacks("gpt-5.6", "gemini-3.7-flash"): when a provider fails, the same request moves to the next model. Also: a Rails stop button that halts a streaming background job through the chat record, and rescue_from on agents. https://paolino.me/rubyllm-2-0/#fallbacks-cancellation-and-errors

### #prompt-caching

An agent resends the same system prompt, tools, and documents on every turn. RubyLLM 2.0 adds chat.with_caching, cache_until_here to mark where the stable part ends, and response.tokens.cache_read to see what was reused. https://paolino.me/rubyllm-2-0/#prompt-caching

### #batches

Most LLM providers charge less for work that can wait. RubyLLM 2.0 stages chats with ask_later, submits them with RubyLLM.batch(chats), and collects the answers from any process with Batch.find, saving them to Rails if you use it. https://paolino.me/rubyllm-2-0/#batches

### #owning-the-transcript

In RubyLLM 2.0 you can rewrite what the model sees with chat.messages =. There's also provider compaction, chat.render to inspect the exact payload without calling the model, and finish reasons normalized across providers. https://paolino.me/rubyllm-2-0/#owning-the-transcript

### #rails-table-ownership

In RubyLLM 2.0 your Rails app has two models: Chat and Message. The model registry, tool calls, usage, and batches live in tables RubyLLM owns, the way Active Storage owns its blobs. New features no longer mean editing classes in your app. https://paolino.me/rubyllm-2-0/#rails-table-ownership

### #prompt-templates

RubyLLM 2.0 puts prompts in app/prompts. RubyLLM.render_prompt("support/instructions", name: user.name) renders ERB and returns a String. Agents find their instructions file by convention, and Rails engines can ship prompts the host app overrides. https://paolino.me/rubyllm-2-0/#prompt-templates

### #workflows-and-instrumentation

RubyLLM 2.0 adds RubyLLM.workflow and workflow.step. They tag every model call, tool call, and usage event inside the block with the workflow and step, so your logs show which task each request belonged to. Your control flow stays plain Ruby. https://paolino.me/rubyllm-2-0/#workflows-and-instrumentation

### #upgrading

Upgrading a Rails app from RubyLLM 1.16 to 2.0: phased migrations you can retry, legacy data kept until you run cleanup, and an optional copy mode with a way back to 1.16. The full path, with the rename table: https://paolino.me/rubyllm-2-0/#upgrading

---

# 2.1

## Release post

X:
RubyLLM 2.1 is out. An MCP client where you choose which tools the model sees, typed judgments, evaluations you can run in CI, tool progress, OpenTelemetry tracing that never exports prompts, and less overhead on every call. https://paolino.me/rubyllm-2-1/

LinkedIn:
I released RubyLLM 2.1 on stage at Deccan Queen on Rails in Pune.

The biggest piece is an MCP client. An MCP server is a Ruby class you own: you pick which of its tools the model sees, rename them, rewrite their descriptions, fix arguments the model shouldn't choose, and require a person's approval before anything destructive runs. Approvals and the server's questions to the user persist in Rails, so a paused call survives a deploy.

2.1 also adds judgments, which turn questions like "is this urgent?" into probabilities your code can branch on. Evaluations run your agent against known answers, have a model grade each one, and fail CI when something regresses. They work from a rake task, RSpec, or Minitest.

Tools can now report progress while they run. RubyLLM::OpenTelemetry.enable traces model calls, tools, and workflows, and exports metadata only, never prompts or responses. And without any code change, streaming, memory use, and Rails persistence do much less work: a 2 MB streamed event went from 116 ms to 2 ms.

Everything, with code, is in the post: https://paolino.me/rubyllm-2-1/

## Section posts

### #mcp

I wrote "Use MCP to prototype. Then replace it with crafted tools you actually control." RubyLLM 2.1 has an MCP client built on that advice: a server is a Ruby class where you pick tools, rewrite descriptions, pin arguments, and require approval. https://paolino.me/rubyllm-2-1/#mcp

### #judgments

How do you know your agent works? RubyLLM 2.1 adds typed judgments (probabilities, choices, and scores your code can branch on) and evaluations you run with bin/rails "ruby_llm:eval[SupportEvaluation]", in CI or as RSpec and Minitest tests. https://paolino.me/rubyllm-2-1/#judgments

### #faster

RubyLLM 2.0 took 116 ms to stream one 2 MB event. 2.1 takes 2 ms, because the old parser rescanned a split line on every network read. The post covers that and the other speedups, with a benchmark task you can run without API keys. https://paolino.me/rubyllm-2-1/#faster

### #opentelemetry

RubyLLM 2.1 adds OpenTelemetry tracing: RubyLLM::OpenTelemetry.enable and every model call, tool run, and workflow is a span in your tracing backend. It uses your SDK and exporters, and exports metadata only, never prompts or responses. https://paolino.me/rubyllm-2-1/#opentelemetry
