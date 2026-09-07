---
layout: post
title: "RubyLLM 2.0"
description: "RubyLLM 2.0 expands the Ruby AI framework with broader provider coverage, audio and video, citations, tool approval, batch processing, and native Rails persistence."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

RubyLLM 2.0 is the biggest update I've worked on since 1.0, and I'm excited to show you what's in it.

The idea is still the same: I want to build AI features in Ruby without learning a different client for every provider. Chat, tools, streaming, embeddings, images, and audio already worked that way.

2.0 covers much more of what those services can do: video and speech generation, document extraction, search, citations, tokenization, and multimodal embeddings. It also adds the controls you need to run this work in an application: resumable agents, human approval, model fallbacks, and accounting for every provider attempt.

RubyLLM is a complete AI framework for Ruby and Rails. Chat is one part of it.

Here's a tour, with separate posts for the details.

## More of the Provider APIs

I compared 1.16 and 2.0 across 40 shared features and seventeen providers. Native coverage went from 171 to 397 provider-feature pairs, out of 407 offered in that comparison. That's a count of supported combinations, not 397 different features or a claim that every provider endpoint is covered.

The [coverage matrix](https://rubyllm.com/next/provider-coverage/) shows what's built in, what needs provider options, and what remains partial. It includes conversations and tools, but also media, documents, search, files, and batches.

```ruby
RubyLLM.speak("Hello!").save("hello.mp3")
RubyLLM.ocr("contract.pdf").markdown
RubyLLM.rerank(query, documents, model: "rerank-v3.5")
RubyLLM.embed("A red panda", with: "panda.jpg", model: "gemini-embedding-2")
RubyLLM.animate("A red panda typing on a keyboard").save("panda.mp4")
RubyLLM.tokenize("Hello, Ruby!", model: "grok-4.3").ids
```

These calls work on their own in Ruby scripts, Rails services, or jobs. They don't need a chat. Streaming and asynchronous jobs are available where the operation supports them. The [new operations](/rubyllm-2-0-new-verbs/) and [speech](/rubyllm-2-0-text-to-speech/) posts show the results and options.

## Run the Agent Loop Yourself

`ask` still runs a conversation for you. When you want to control the steps:

```ruby
chat = RubyLLM.chat.with_tools(SearchDocs).ask_later("How do I configure webhooks?")
chat.step until chat.complete? || chat.awaiting_approval?
```

`ask_later` stages the question. `generate` makes a model call. `run_tools` executes pending calls. `step` chooses the next move, and `complete` keeps going until the answer is ready or approval is needed.

For Rails agents, a job can load through `SupportAgent.find(chat_id)` and continue from the saved transcript. It reapplies the tools and configuration, then runs only the calls whose results haven't been saved. Tools that write still need idempotency, as with any retryable job.

The [agentic loop post](/rubyllm-2-0-agentic-loop/) shows the job and cancellation examples.

## Approve a Tool Call

Some actions should wait for a person:

```ruby
class RefundOrder < RubyLLM::Tool
  parameter :order_id, description: "ID of the order to refund"
  requires_approval

  def execute(order_id:, tool_call: nil)
    Refunds.issue(order_id:, idempotency_key: tool_call.id)
  end
end
```

The example's `Refunds.issue` is your application service, using the call ID to avoid issuing the same refund twice.

`chat.pending_approvals` gives you the calls to show the user. `chat.approve(call)` or `chat.deny(call)` records a decision, and `chat.complete` continues. In Rails, the decision is saved on the tool-call record, so the worker can finish while the user decides.

[Tool approval](/rubyllm-2-0-requires-approval/) is one of my favorite additions. It fits into the job and controller your app already has.

## Count the Attempts, Including Failed Ones

A cancelled stream can use tokens without producing a saved message. So can a failed attempt before a retry. 2.0 records usage per provider attempt, while the API stays small:

```ruby
response.tokens.input
response.cost.total
chat.cost.total
```

Costs are frozen when the attempt finishes. Missing usage or pricing can make a total `nil`; RubyLLM doesn't fill the gap with zero. Provider-reported charges take precedence over estimates when available.

The [cost and usage post](/rubyllm-2-0-cost-and-usage-tracking/) explains what the totals include and where uncertainty remains.

## Batch the Work That Can Wait

Stage chats with `ask_later`, then submit them with `RubyLLM.batch(chats)`. Collect the responses later, from another process if needed. Embedding requests can be staged with `embed_later` too.

RubyLLM applies the available batch rates to collected results. In Rails, it saves batch state internally and writes answers back to your chats. [The batch post](/rubyllm-2-0-batches/) shows collection, polling, and costs.

For repeated live requests, [prompt caching](/rubyllm-2-0-prompt-caching/) has its own API:

```ruby
chat.with_caching(ttl: "1h")
chat.with_instructions(review_guidelines).cache_until_here
```

Choose options for the provider you're using. Gemini and Vertex AI explicit caches use `RubyLLM.cache`, with `renew` and `delete` to manage the resource.

## Search, Files, and Citations

`with_server_tools(:web_search)` enables search on supported providers. Code execution, file search, and remote MCP connectors use the same method where available. Raw tool definitions can pass through when RubyLLM doesn't have an alias yet.

[`RubyLLM.upload`](/rubyllm-2-0-files-and-attachments/) lets you reuse provider-managed files. Eligible large local attachments can upload automatically, and Ruby tools can return files alongside text.

`with_citations` makes attached documents citable on supported models. Search citations are parsed automatically. Both use `response.citations`, so your UI can read source URLs, quotes, and positions through the same objects.

The [server tools](/rubyllm-2-0-server-tools/) and [citations](/rubyllm-2-0-citations/) posts show how they work together.

## Thinking and Token Counting

Enable thinking with `chat.with_thinking`, or choose an effort or token budget the model supports. Read the returned reasoning through `response.thinking`, and its usage through `response.tokens.thinking`.

`chat.count_tokens(text)` counts a proposed question with the configured history before generation, without saving it. `RubyLLM.tokenize` exposes the token IDs for a string. The [tokenization guide](https://rubyllm.com/next/tokenization/) explains the distinction and which request settings the counting endpoint includes.

## Handle the Unhappy Paths

`with_fallbacks` sets backup models for transient failures. `cancel` requests a stop; in Rails, the signal goes through the database so your web process can cancel a background stream. Agent instances can use `rescue_from` for their error policy.

[Fallbacks and cancellation](/rubyllm-2-0-fallbacks-and-cancellation/) includes the streaming details. A half-written answer needs different UI handling from a request that never started.

## Control the Request

On a plain chat, `messages=` replaces the model-facing transcript. On a Rails record, use `to_llm.messages=` for a temporary replacement or a separate association for durable history management.

`with_compaction` enables supported provider compaction. `before_request` lets you edit the rendered payload, and `render` lets you inspect it. Finish reasons arrive as symbols such as `:stop` and `:max_tokens`.

The [transcript post](/rubyllm-2-0-own-the-transcript/) shows where these controls help and what to preserve in tool conversations.

## Providers and Protocols

2.0 separates providers from protocols. OpenAI defaults to Responses, and providers such as Vertex AI and Bedrock can route each model through its supported API format.

Cohere, Ollama Cloud, ElevenLabs, and Deepgram bring the total to seventeen. You can also scaffold a provider gem:

```bash
ruby_llm provider-gem Acme --api-base https://api.acme.ai/v1
```

The [providers and protocols post](/rubyllm-2-0-providers-and-protocols/) walks through the design and generator. `RubyLLM.models.refresh` updates and persists the registry without a gem release.

## Less Bookkeeping in Your Rails App

Your app owns `Chat` and `Message`. RubyLLM owns its supporting registry, tool-call, usage, and batch tables. [The Rails post](/rubyllm-2-0-rails-table-ownership/) explains the change.

Prompts render from ERB files in `app/prompts`, and named agents find their instructions by convention. [`RubyLLM.render_prompt`](/rubyllm-2-0-prompt-templates/) makes the renderer available anywhere you need a string.

[`RubyLLM.workflow`](/rubyllm-2-0-workflows-and-instrumentation/) groups instrumentation from a task and its steps. Your orchestration stays in Ruby; the events get names and IDs you can follow in your logs.

The small API details got attention too. Value setters use `nil` to clear a setting. Feature switches such as `with_thinking` and `with_caching` use `false` to disable it. Tools have one set of declaration names: `description`, `parameter`, and `parameters`.

## Help Your Coding Assistant Use 2.0

The gem includes a RubyLLM coding skill, maintained with the code and guides. Install the copy that matches your application's bundle:

```bash
npx skills add "$(bundle show ruby_llm)" --skill rubyllm
```

It gives the assistant the current API conventions and documentation, including the Rails integration. That helps avoid generated code using an old method name or rebuilding something RubyLLM already does. The [coding assistant guide](https://rubyllm.com/next/ai-coding-assistants/) has the setup details.

## Upgrading

The [upgrade walkthrough](/rubyllm-2-0-upgrading/) starts from 1.16. The generator writes prepare, backfill, and finish migrations, with cleanup generated separately after verification. Optional copy mode gives you a controlled way to return to 1.16: conversations written by 2.0 remain stored but hidden during that rollback. Rehearse with both application builds and keep affected activity paused during migrations and version switches.

The [2.0 documentation](https://rubyllm.com/next/) covers all of this in more detail. Thanks to everyone testing the development version, filing issues, and helping get these APIs into shape. There is a lot here I've wanted to use in my own apps, and I'm looking forward to seeing it in yours.
