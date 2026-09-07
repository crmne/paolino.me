# RubyLLM 2.0 X post series

Draft copy to pair with the matching blog posts. Replace [link] when each post goes live.

## 1. Providers and protocols

I've separated providers from protocols in RubyLLM 2.0. OpenAI defaults to Responses, and services like Vertex AI can route each model through its own API format.

There are seventeen providers, plus a generator for building your own provider gem.

[link]

## 2. The agentic loop

RubyLLM has run the tool loop inside ask since 1.0. In 2.0, you can drive each move yourself:

chat.generate
chat.run_tools
chat.step

Run a turn in a Rails job, save the result, and continue in another worker. I'm looking forward to using this.

[link]

## 3. Tool approval

I want an agent to look up an order by itself. I'd like it to ask before issuing the refund.

RubyLLM 2.0 tools can declare requires_approval. Use chat.pending_approvals, call chat.approve(call) or chat.deny(call), then continue. Rails saves the decision.

[link]

## 4. Server tools

Web search in RubyLLM 2.0:

chat.with_server_tools(:web_search)

The provider runs the search. Sources come back on response.citations. Code execution uses the same method where supported. New tool definitions can pass through as hashes.

[link]

## 5. Citations

An answer about a contract is more useful when you can open the passage it refers to.

RubyLLM 2.0 adds document citations with with_citations on supported models. Search citations are parsed automatically. Both come back as RubyLLM::Citation objects.

[link]

## 6. Batches

An overnight classification job can wait for a batch:

chats = records.map { |r| RubyLLM.chat.ask_later(r.prompt) }
batch = RubyLLM.batch(chats)

RubyLLM 2.0 collects the answers later and applies available batch pricing. Stage embedding requests with embed_later and submit them through the same API.

[link]

## 7. Prompt caching

That long system prompt gets sent again on every tool round.

RubyLLM 2.0 adds with_caching and cache_until_here for provider caching. Read tokens.cache_read and tokens.cache_write to check usage. Disable the controls with with_caching(false).

[link]

## 8. Cost and usage

A cancelled stream can use tokens without leaving a saved message.

RubyLLM 2.0 records provider attempts so chat.cost.total includes work the transcript misses. Missing usage or pricing leaves the total unknown. I don't want missing data to look free.

[link]

## 9. Fallbacks and cancellation

RubyLLM 2.0 lets a chat try backups on transient failures:

chat.with_fallbacks("gpt-4.1-mini", "claude-haiku-4-5")

And chat.cancel requests a stop. With Rails persistence, the stop button in the web process can cancel a stream running in a worker.

[link]

## 10. Files and attachments

file = RubyLLM.upload("manual.pdf", provider: :anthropic)

RubyLLM 2.0 can reuse that file in compatible chats without resending the bytes. Large eligible attachments upload automatically.

Tools can return files now. A chart tool can return its chart.

[link]

## 11. New verbs

New in RubyLLM 2.0:

RubyLLM.animate("A red panda typing").save("panda.mp4")
RubyLLM.ocr("scan.pdf").markdown
RubyLLM.rerank(query, docs, model: "rerank-v3.5")

RubyLLM.tokenize(text, model: "grok-4.3").ids

Inspect token IDs, or call chat.count_tokens to size a request before generation. These operations work in scripts, services, and jobs.

[link]

## 12. Text to speech

RubyLLM.speak("Your order shipped.").save("update.mp3")

I've wanted this beside transcribe for a while. RubyLLM 2.0 can take a voice message, ask a model to answer, and generate speech from the reply. Pick models and voices from the supported providers.

[link]

## 13. Prompt templates

I don't enjoy editing long prompts in Ruby heredocs.

RubyLLM 2.0 adds RubyLLM.render_prompt for ERB in app/prompts. Named agents find their instructions by convention. WorkAssistant.sync_instructions(chat) saves updated wording to an existing chat.

[link]

## 14. Own the transcript

Keep the user's full conversation and send the model a shorter history.

A RubyLLM chat accepts chat.messages = messages_for_model. On Rails records, use to_llm.messages= for a temporary change, or a separate association for durable history management.

[link]

## 15. Provider generator

ruby_llm provider-gem Acme --api-base https://api.acme.ai/v1

RubyLLM 2.0 scaffolds a provider gem with specs, CI, and a model-catalog task. Fill in the service's details and reuse its protocol. Your provider doesn't have to wait for the main gem.

[link to the providers and protocols post]

## 16. Rails table ownership

A fresh RubyLLM 2.0 install gives your Rails app two models: Chat and Message.

RubyLLM owns its registry, tool calls, usage, and batches. Your app keeps the conversations and its product rules. Two fewer application models to maintain than in 1.16.

[link]

## 17. Request controls

A few RubyLLM 2.0 details I like:

with_max_output_tokens caps the answer.
count_tokens sizes a supported request before generation.
render shows the payload.
finish_reason returns symbols like :stop and :max_tokens across providers.

[link to the transcript post]

## 18. Workflows and instrumentation

I want to find an agent pipeline's calls together in my logs.

RubyLLM.workflow("Write article", id: "article-42") adds that identity to nested events. workflow.step names each part. The blocks run your Ruby code and return its normal values.

[link]

## 19. Upgrading

I've put a lot into the RubyLLM 2.0 upgrade path.

The generator writes prepare, backfill, and finish migrations. Optional copy mode keeps a controlled route to 1.16: conversations changed by 2.0 remain stored but hidden during rollback. Both builds need the generated compatibility files. Version switches pause writers; no dual writes. Cleanup comes later.

[link]

## 20. Overview

RubyLLM 2.0 is a Ruby AI framework: conversations, tools, agents, audio, video, documents, search, and batches.

Across 40 shared features and seventeen providers, native coverage went from 170 to 395 provider-feature pairs out of 405 offered. The matrix shows the details. Here's the tour.

[link]

## 21. Coding assistant skill

RubyLLM 2.0 includes a coding skill with the gem:

npx skills add "$(bundle show ruby_llm)" --skill rubyllm

Install the copy that matches your app's bundle so your coding assistant can use the current API and guides.

[link to the coding assistant guide]
