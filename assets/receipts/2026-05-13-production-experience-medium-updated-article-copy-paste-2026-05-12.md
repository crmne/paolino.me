# Updated Medium Article About RubyLLM

This is the replaced version of the Medium article, copied from Medium by Carmine on 2026-05-12.

Source URL:
https://mrrazahussain.medium.com/the-rails-llm-stack-is-finally-ready-for-production-here-is-what-i-learned-shipping-it-ff9d20298c5c

---

RubyLLM in production: streaming failures, token budgets, provider fallback, and what the tutorials skip

This is the Updated version. Every code example below has been verified against the official RubyLLM documentation.

Python teams have been shipping LLM features for two years while Rails developers duct-taped together hand-rolled HTTP clients or bent Langchain.rb into shapes it was never designed for. The gap was real.

RubyLLM closes most of it. But the README covers the happy path. This covers what the happy path leaves out — the configuration, failure modes, and architectural decisions you need to make before putting real users on it.

RubyLLM is a Ruby gem that wraps multiple LLM providers behind a unified interface. One configuration, multiple backends. OpenAI, Anthropic, Google Gemini, and others sit behind the same API surface.

The pitch sounds like every other abstraction layer. The difference is that RubyLLM was designed from the start to fit Rails conventions rather than fighting them. ActiveRecord integration for chat persistence via acts_as_chat. Streaming that plays well with Turbo Streams. Tool use that maps to plain Ruby classes.

RubyLLM provides a unified interface across OpenAI, Anthropic, Gemini, and more
Chat persistence via ActiveRecord is built in through acts_as_chat, not bolted on
Streaming uses standard Ruby block syntax, not custom adapter code

## What Breaks First When You Go Beyond the Tutorial

The tutorial shows this:

```ruby
chat = RubyLLM.chat
response = chat.ask "Hello"
puts response.content
```

That works in development. The problem shows up under real traffic.

The streaming response from the provider comes over an open HTTP connection. If the connection drops mid-stream — a Puma worker restart, a timeout, a transient network hiccup — RubyLLM raises RubyLLM::ServiceUnavailableError or RubyLLM::ServerError. There is no partial response recovery. You need to configure retries before this hits users, not after.

RubyLLM has built-in retry configuration you should set explicitly before going to production:

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure do |config|
  config.openai_api_key         = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key      = ENV["ANTHROPIC_API_KEY"]
  config.max_retries            = 3
  config.retry_interval         = 0.5
  config.retry_backoff_factor   = 2
  config.retry_interval_randomness = 0.5
end
```

If you need to handle failures at the call site and show the user a specific error:

```ruby
def stream_response(prompt)
  chat = RubyLLM.chat(model: "gpt-4o")
  chat.ask(prompt) do |chunk|
    broadcast_chunk(chunk)
  end
rescue RubyLLM::ServiceUnavailableError, RubyLLM::ServerError => e
  broadcast_error("Provider unavailable, try again shortly.")
end
```

Configure max_retries in the initializer — it covers most transient failures automatically
Rescue RubyLLM::ServiceUnavailableError and RubyLLM::ServerError at the call site for user-facing error handling
RubyLLM::RateLimitError is also in the retry list by default

## The Token Budget Problem Nobody Mentions in the Getting Started Guide

Build a multi-turn chat feature with acts_as_chat and it accumulates every message in the database automatically. RubyLLM sends that entire history with every request. That is the intended behavior. It is also a cost trap.

A user with 47 messages in a thread who asks one follow-up question pays for all 47 messages in input tokens every time. With GPT-4o pricing, a long thread crosses $0.30 per request fast. The problem compounds with your most engaged users — exactly the ones you want to keep.

RubyLLM does not truncate your message history. That decision belongs to you.

One thing to understand before picking an approach: acts_as_chat manages message history internally. When you call chat.ask(prompt) on a persisted chat model, it sends every message in chat.messages to the provider automatically. You do not pass a custom array. Sliding window helpers that return a mapped array have no effect here unless you also control what is in the database.

There are two approaches to context management with acts_as_chat. Pick one.

Option 1: Delete old messages from the database before asking.

This keeps acts_as_chat in control and trims history at the database level:

```ruby
MAX_CONTEXT_MESSAGES = 8
def trim_context(chat)
  message_ids = chat.messages.order(:created_at).pluck(:id)
  return if message_ids.size <= MAX_CONTEXT_MESSAGES
  ids_to_delete = message_ids[0..-(MAX_CONTEXT_MESSAGES + 1)]
  chat.messages.where(id: ids_to_delete).destroy_all
end
# In your controller or job:
trim_context(current_chat)
current_chat.ask(params[:prompt]) do |chunk|
  broadcast_chunk(chunk)
end
```

Destructive — those messages are gone from the database. Acceptable for most chat UIs where you display the full thread visually but do not need old messages in the LLM context.

Option 2: Skip acts_as_chat and manage the message array yourself.

If you need fine-grained control — pinning early messages, custom context shapes — manage messages manually and pass them to a plain RubyLLM.chat object:

```ruby
MAX_RECENT = 6
def build_context(persisted_messages)
  first_user = persisted_messages.find { |m| m.role == "user" }
  recent = persisted_messages.last(MAX_RECENT)
  base = []
  if persisted_messages.size > 12 && first_user && !recent.include?(first_user)
    base << { role: "user", content: first_user.content }
    base << { role: "assistant", content: "Understood. Continuing from that context." }
  end
  base + recent.map { |m| { role: m.role, content: m.content } }
end
def ask_with_context(persisted_chat, prompt)
  messages = build_context(persisted_chat.messages.order(:created_at).to_a)
  chat = RubyLLM.chat(model: "gpt-4o")
  messages.each { |m| chat.add_message(role: m[:role], content: m[:content]) }
  chat.ask(prompt)
end
```

The !recent.include?(first_user) check matters. Without it, if the first user message falls within the last 6, you send it twice and pay for it twice.

Add a UI nudge to start a new thread at around 30 messages. Beyond that, even with pinning, context degradation becomes noticeable.

acts_as_chat sends all persisted messages automatically — a sliding window helper has no effect unless you control what is in the database
To trim context with acts_as_chat: delete old messages before calling ask
To pin early messages: manage the message array yourself and replay it into a plain RubyLLM.chat object

## Why Provider Fallback Is Not Optional in Rails LLM Production

OpenAI has had multiple partial outages. When your feature has a single provider and that provider goes down, users see a spinner that never resolves. That is a solvable architecture problem.

Provider switching in RubyLLM is straightforward — the provider is inferred from the model name, so you switch by switching models:

```ruby
def ask_with_fallback(prompt)
  RubyLLM.chat(model: "gpt-4o").ask(prompt)
rescue RubyLLM::ServiceUnavailableError, RubyLLM::ServerError => e
  Rails.logger.warn "OpenAI unavailable: #{e.message}, falling back to Anthropic"
  RubyLLM.chat(model: "claude-sonnet-4").ask(prompt)
end
```

For a Redis-backed circuit breaker that avoids hammering a down provider on every request:

```ruby
class ProviderCircuitBreaker
  FAILURE_THRESHOLD = 5
  RESET_WINDOW = 120 # seconds
  def self.available?(provider)
    $redis.get("llm:failures:#{provider}").to_i < FAILURE_THRESHOLD
  end
  def self.record_failure(provider)
    key = "llm:failures:#{provider}"
    $redis.incr(key)
    $redis.expire(key, RESET_WINDOW)
  end
  def self.record_success(provider)
    $redis.del("llm:failures:#{provider}")
  end
end
PROVIDER_MODELS = {
  "openai"    => "gpt-4o",
  "anthropic" => "claude-sonnet-4"
}.freeze
# One pass, one Redis call per provider - no double-counting
def providers_in_priority_order
  available, unavailable = PROVIDER_MODELS.partition do |provider, _|
    ProviderCircuitBreaker.available?(provider)
  end
  available + unavailable
end
def chat_with_fallback(prompt)
  last_error = nil
  providers_in_priority_order.each do |provider, model|
    begin
      response = RubyLLM.chat(model: model).ask(prompt)
      ProviderCircuitBreaker.record_success(provider)
      return response
    rescue RubyLLM::ServiceUnavailableError, RubyLLM::ServerError => e
      ProviderCircuitBreaker.record_failure(provider)
      last_error = e
      next
    end
  end
  raise last_error
end
```

This iterates through providers and only raises after all of them fail. Using partition instead of separate select and reject calls does one Redis round trip per provider rather than two, which also eliminates the window where a provider crosses the threshold between the two calls and appears in both lists.

One caveat: gpt-4o and claude-sonnet-4 are not equivalent. Some prompts produce materially different output across providers. Test your prompts against both before treating fallback as transparent.

A single-provider LLM feature is a single point of failure; treat it like any other external dependency
Provider switching in RubyLLM works by specifying a different model string — no separate client instantiation
The circuit breaker must actually retry with the fallback on failure, not just record and raise

## Streaming With Turbo Streams Is One Configuration Line Away From Silent Failure

The default nginx configuration buffers proxy responses. When your Rails app streams SSE chunks, nginx accumulates them and flushes in one burst. Users see a spinner, then the full response appears instantly. It looks like streaming is broken.

The fix is two lines — one in nginx, one in the controller:

```nginx
location /ai/stream {
  proxy_pass http://rails_app;
  proxy_buffering off;
  proxy_set_header X-Accel-Buffering no;
}
```

On the Rails side, set the header explicitly as well:

```ruby
def stream
  response.headers["X-Accel-Buffering"] = "no"
  response.headers["Cache-Control"]      = "no-cache"
  chat = current_chat  # acts_as_chat model
  chat.ask(params[:prompt]) do |chunk|
    next if chunk.content.nil? || chunk.content.empty?
    Turbo::StreamsChannel.broadcast_append_to(
      current_chat,
      target:  "response_content",
      partial: "chats/chunk",
      locals:  { content: chunk.content }
    )
  end
end
```

The Turbo Stream partial is just a span. The chunk arrives, gets appended, browser renders it progressively.

One load concern worth knowing before you launch: each streaming request holds an open connection for the full response duration. A complex prompt runs 8–12 seconds. With 40 concurrent users streaming, ActionCable memory adds up fast. Load-test this specifically — it is not covered by standard Rails load tests.

Disable nginx and CDN buffering explicitly; the default batches your stream into a single response
Set X-Accel-Buffering: no at both the Rails controller level and the nginx proxy level
Load-test ActionCable under concurrent streaming before launch; it behaves differently from standard request/response load

## What the Rails vs Python LLM Gap Actually Looks Like Now

The fundamental features you need for a production LLM feature in a Rails app are all there in RubyLLM. Chat persistence, streaming, tool use, multi-provider support. None of it requires leaving the Rails idiom.

What is still missing is the layer above. Evaluation tooling. Prompt versioning. Automated regression testing for LLM outputs. The Python ecosystem has libraries for all of this — LangSmith, PromptFlow, and others. Ruby does not, not yet. You will end up building your own lightweight eval harness if you need it.

The gap has closed at the infrastructure layer. It is still wide at the tooling layer.

That is fine for most Rails apps shipping a focused LLM feature. Chat interface, summarization endpoint, classification step in a background job — RubyLLM handles all of it without asking you to learn a new paradigm.

If you are building something that requires complex agent orchestration or retrieval pipelines at scale, you will hit the ceiling faster in Ruby than in Python. That ceiling moved up considerably this year. It did not disappear.

RubyLLM covers the core production requirements for focused LLM features in Rails apps
Evaluation, prompt versioning, and regression testing tooling does not exist in Ruby at the same depth as Python
For agent orchestration beyond simple tool use, the Python ecosystem is still materially deeper

If you are shipping an LLM feature in Rails and hit something this guide missed, the RubyLLM documentation at rubyllm.com is the authoritative reference.

Related reads

GPT-5.5 vs Claude Opus 4.7: Which One Should Rails Developers Actually Use?
Your AI Agent Is Burning Tokens Before You Type a Word

This story is published on Generative AI. Connect with us on LinkedIn and follow Zeniteq to stay in the loop with the latest AI stories.

Subscribe to our newsletter and YouTube channel to stay updated with the latest news and updates on generative AI. Let’s shape the future of AI together!
