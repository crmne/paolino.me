# Original Medium Article About RubyLLM

This is the first version of the Medium article, before it was replaced after being called out.

---

Python teams have been shipping RubyLLM features for two years while Rails developers duct-taped together hand-rolled HTTP clients or bent Langchain.rb into shapes it was never designed for. The gap was real. The cost of crossing it was real. I know because I spent three weeks on the wrong side of it before we finally had something stable in production.

This is not a walkthrough of the happy path. The happy path is in the README. This is what broke on day one, day four, and day eleven -- and why none of it showed up in any tutorial I found.

RubyLLM is a Ruby gem that wraps multiple LLM providers behind a unified interface. One client, one configuration, multiple backends. OpenAI, Anthropic, Google Gemini, and others sit behind the same API surface.

The pitch sounds like every other abstraction layer. The difference is that RubyLLM was designed from the start to fit Rails conventions rather than fighting them. ActiveRecord integration for chat persistence. Streaming that plays well with Turbo Streams. Tool use that maps to Ruby objects cleanly.

I had looked at Langchain.rb before this. We ran it in staging for about six weeks on a client project. The abstractions leaked in ways that were hard to debug, the documentation was three versions behind the code, and every time we needed to do something slightly off the tutorial path we ended up reading source.

RubyLLM is not perfect. But it is the first Ruby LLM library that felt like it was written for Rails developers rather than ported to them.

RubyLLM provides a unified interface across OpenAI, Anthropic, and Google Gemini backends
Chat persistence via ActiveRecord is built in, not bolted on
Streaming integrates with Turbo Streams without custom adapter code

## What Breaks First When You Go Beyond the Tutorial

The tutorial shows this.

```ruby
client = RubyLLM.client
response = client.chat(messages: [{ role: "user", content: "Hello" }])
puts response.content
```

That works. Ship it to staging and it still works. Put real users on it and within forty minutes you will see your first `RubyLLM::StreamInterrupted` exception in the logs.

I thought it was a network fluke the first time. Dismissed it. Saw it again six hours later. Started paying attention when we had eleven in a single hour during a load spike.

What was happening was not complicated once I understood it. The streaming response from OpenAI comes in chunks over an open HTTP connection. If the connection drops mid-stream for any reason -- a Puma worker restart, a timeout, a transient network hiccup -- RubyLLM raises StreamInterrupted. There is no automatic retry. There is no partial response recovery.

The fix we shipped was a rescue wrapper with retry logic at the controller layer.

```ruby
def stream_response(prompt, retries: 2)
  attempts = 0
  begin
    client.chat(
      model: "gpt-4o",
      messages: [{ role: "user", content: prompt }],
      stream: proc { |chunk| broadcast_chunk(chunk) }
    )
  rescue RubyLLM::StreamInterrupted => e
    attempts += 1
    retry if attempts <= retries
    broadcast_error("Stream interrupted after #{attempts} attempts")
  end
end
```

That alone cut our error rate by 84%. The remaining 16% were genuine provider outages where retrying would not have helped anyway.

RubyLLM::StreamInterrupted is not documented prominently but it fires constantly in real traffic
Wrap streaming calls with retry logic before you go to production, not after
Two retries covers most transient failures; beyond that you are dealing with a real outage

## The Token Budget Problem Nobody Mentions in the Getting Started Guide

We had a feature that let users ask follow-up questions in a chat thread. Standard enough. The implementation accumulated messages in the ActiveRecord chat history and sent them with every request.

On day four of production, one user had a 47-message thread. A single follow-up question triggered a request that cost $0.31 in tokens. We noticed because that user had asked eleven follow-ups in one session and our daily budget alarm fired at 2pm instead of never.

The problem is straightforward but the solution requires a decision you have to make consciously. RubyLLM does not truncate your message history. It sends what you give it. If you give it the entire thread, you pay for the entire thread on every request.

We tried a naive sliding window first. Keep the last N messages. The number we landed on after two days of testing was 8 messages -- 4 exchanges. Beyond that, response quality for our specific use case did not improve noticeably and cost climbed steeply.

```ruby
MAX_CONTEXT_MESSAGES = 8
def build_context(chat)
  messages = chat.messages.order(:created_at).last(MAX_CONTEXT_MESSAGES)
  messages.map { |m| { role: m.role, content: m.content } }
end
```

That was not good enough for longer threads where early context mattered. We ended up building what I now call the pinned-context pattern. One system message always included, one pinned user message if the thread had more than 12 messages, then the sliding window.

```ruby
def build_context(chat)
  base = [{ role: "system", content: chat.system_prompt }]
  if chat.messages.count > 12
    first_user_message = chat.messages.where(role: "user").order(:created_at).first
    base << { role: "user", content: first_user_message.content } if first_user_message
    base << { role: "assistant", content: "Understood. Continuing from that context." }
  end
  recent = chat.messages.order(:created_at).last(6).map do |m|
    { role: m.role, content: m.content }
  end
  base + recent
end
```

Not elegant. But it cut our per-conversation cost by 61% without users noticing any quality drop on threads shorter than 30 messages. Above 30 messages the degradation became visible. We added a UI nudge at that point to start a new thread.

Uncapped message history is a cost bomb waiting for your most engaged users
A sliding window of 6-8 messages covers most use cases without noticeable quality loss
For threads where early context matters, pin the first user message rather than expanding the window

## Why Provider Fallback Is Not Optional in Rails LLM Production

We launched with OpenAI as the only provider. That lasted nine days before OpenAI had a partial API outage that lasted 23 minutes during peak hours. Our feature was completely dark for those 23 minutes. Users saw a spinner that never resolved.

I had treated provider fallback as a nice-to-have for v2. It became a v1 requirement after that incident.

RubyLLM makes the switching easy. The provider is a parameter on the chat call. The hard part is not the switching code, it is knowing when to switch.

We built a circuit breaker pattern around provider calls. Not a full gem-level circuit breaker, just a simple Redis-backed counter.

```ruby
class ProviderCircuitBreaker
  FAILURE_THRESHOLD = 5
  RESET_WINDOW = 120 # seconds
  def self.available?(provider)
    failures = $redis.get("llm:failures:#{provider}").to_i
    failures < FAILURE_THRESHOLD
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
```

Then the call site selects a provider based on availability.

```ruby
PROVIDERS = ["openai", "anthropic"].freeze
def select_provider
  PROVIDERS.find { |p| ProviderCircuitBreaker.available?(p) } || PROVIDERS.first
end
def chat_with_fallback(messages)
  provider = select_provider
  client = RubyLLM.client(provider: provider)
  response = client.chat(model: preferred_model(provider), messages: messages)
  ProviderCircuitBreaker.record_success(provider)
  response
rescue RubyLLM::APIError => e
  ProviderCircuitBreaker.record_failure(provider)
  raise
end
```

The preferred_model method maps each provider to the closest equivalent model. That mapping took longer to get right than the circuit breaker code. GPT-4o and Claude Sonnet 4 are not equivalent in every output characteristic, and some of our prompts needed tuning per provider.

Still not fully there, honestly. The model parity problem is real and ongoing.

A single-provider LLM feature is a single point of failure; treat it like any other external dependency
A Redis-backed failure counter is enough for basic circuit breaking; you do not need a full library
Model equivalency across providers requires prompt testing, not just a mapping table

## Streaming With Turbo Streams Is One Configuration Line Away From Silent Failure

The RubyLLM documentation shows streaming with a plain proc. That works in a standard controller action. It does not work the way you expect inside a Turbo Stream response without one specific configuration that is easy to miss.

We built our initial streaming implementation against a regular controller action. Tested it locally, worked fine. Deployed it, tested it in staging, worked fine. First user reports came in two hours after production launch: the response appears all at once after a delay instead of streaming progressively.

The issue is that Rack buffers the response body unless you explicitly disable buffering for that route. In our nginx configuration, X-Accel-Buffering was not set, so nginx was buffering the SSE stream. The tokens accumulated server-side and flushed in a single burst.

```nginx
location /ai/stream {
  proxy_pass http://rails_app;
  proxy_buffering off;
  proxy_set_header X-Accel-Buffering no;
}
```

On the Rails side, the controller action needs to set the header explicitly as well, because we use a CDN that checks for it independently.

```ruby
def stream
  response.headers["X-Accel-Buffering"] = "no"
  response.headers["Cache-Control"] = "no-cache"
  client = RubyLLM.client
  client.chat(
    model: "gpt-4o",
    messages: build_context(current_chat),
    stream: proc { |chunk|
      content = chunk.content
      next if content.nil? || content.empty?
      Turbo::StreamsChannel.broadcast_append_to(
        current_chat,
        target: "response_content",
        partial: "chats/chunk",
        locals: { content: content }
      )
    }
  )
end
```

The Turbo Stream partial is just a span. Nothing fancy. The chunk arrives, gets appended, browser renders it. Progressive streaming restored.

What I did not expect was the load this put on ActionCable. Each streaming request holds a connection open for the full response duration. On GPT-4o with a complex prompt that can be 8-12 seconds. With 40 concurrent users streaming, our ActionCable memory usage was not something I had load-tested at all.

Disable nginx and CDN buffering explicitly; the default will batch your stream into a single response
Set X-Accel-Buffering: no at both the Rails controller level and the nginx proxy level
ActionCable memory under concurrent streaming load needs a dedicated load test before launch

## What the Rails vs Python LLM Gap Actually Looks Like Now

I spent time in 2024 looking at what Python teams were doing with LangChain and LlamaIndex. The ecosystem depth was not even comparable. They had retrieval-augmented generation pipelines, agent frameworks, embedding stores, evaluation tooling. We had gems that wrapped the OpenAI HTTP API.

RubyLLM rails production use is genuinely different now. The fundamental features you need for a production LLM feature in a Rails app are all there. Chat persistence, streaming, tool use, multi-provider support. None of it requires leaving the Rails idiom.

What is still missing is the layer above that. Evaluation tooling. Prompt versioning. Automated regression testing for LLM outputs. The Python ecosystem has libraries for all of this. Ruby does not, not yet. We built our own lightweight eval harness using RSpec fixtures and a scoring rubric. It works. It is not something I would want to maintain long-term.

The gap has closed at the infrastructure layer. It is still wide at the tooling layer.

That is actually fine for most Rails apps shipping a focused LLM feature. If you are building a chat interface, a summarization endpoint, a classification step in a background job, RubyLLM gets you there without asking you to learn a new paradigm.

If you are building something that requires complex agent orchestration or retrieval pipelines at scale, you are still going to hit the ceiling faster in Ruby than in Python. That ceiling moved up considerably this year. It did not disappear.

RubyLLM covers the core production requirements for focused LLM features in Rails apps
Evaluation, prompt versioning, and regression testing tooling does not exist in Ruby yet at the same depth as Python
For agent orchestration beyond simple tool use, the Python ecosystem is still materially deeper
