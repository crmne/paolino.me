---
layout: post
title: "RubyLLM 2.1 Is Faster: Where the Time Went"
date: 2026-10-08 14:40:00 +0530
description: "RubyLLM 2.1 streams, remembers, and connects with far less overhead. What was slow in 2.0, why, and how to measure it yourself."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM, Performance]
---
RubyLLM 2.1 is out, and it streams a single 2 MB event in 2 milliseconds. RubyLLM 2.0 took 116.

A common view is that an LLM library's speed doesn't matter, because the model takes seconds to answer. That view misses three things. Streaming code runs once per chunk, so a little waste per chunk is a lot of waste per reply. Memory a chat keeps for each turn adds up across a forty-turn conversation and a few hundred conversations per process. And anything quadratic stays hidden behind small test inputs until a user sends a large image.

For 2.1 I took the providers out of the picture and measured what RubyLLM itself costs. These are the results, 2.0.0 against 2.1 on the same machine:

| Workload | 2.0 | 2.1 |
| --- | --- | --- |
| Stream 500 text deltas from Anthropic | 9.8 ms | 4.1 ms |
| Stream a 2 MB event that arrives in 16 KB pieces | 116 ms | 2.0 ms |
| Stream 500 Perplexity chunks that each cite 20 sources | 137 ms | 17 ms |
| Ask a Bedrock chat with 200 messages of history | 2.9 ms | 0.40 ms |
| Embed 100 texts and read the 2.4 MB response | 4.5 ms | 2.2 ms |
| Memory kept by a streamed 40-turn chat with a 256 KB image | 28 MB | 0.48 MB |
| Eight threads loading the model registry at once | 273 ms | 32 ms |
| Twenty Vertex AI calls with a service account key | 20 token requests | 1 token request |
| Rebuild a persisted 100-message chat | 11.4 ms | 6.8 ms |
| The same chat without `automatic_scope_inversing` | 58 queries | 8 queries |
| Check `awaiting_approval?` on a chat with ten 1 MB images | 10 downloads | none |

Providers answer from canned responses, so these times are RubyLLM's own work and nothing else. They're medians from an AMD Ryzen 9 9900X on Ruby 4.0.7.

None of this needs a code change. The sections below explain the larger improvements.

## The 2 MB Event That Took 116 ms

Providers stream over server-sent events: lines of `data: ...` separated by blank lines. Most events are tiny, a few tokens each. Some aren't. An image generation stream can deliver a whole image, base64-encoded, as one event, and the network hands it to you in pieces of whatever size it likes.

RubyLLM used the `event_stream_parser` gem, which slices each line off its buffer with a regular expression. When a line spans several network reads, there's no line break yet, so the search fails, and on the next read it starts again from the beginning of the line. A 2 MB event in 16 KB pieces is 128 reads. The parser scans the first piece 128 times, the second 127 times, and so on. That's quadratic, and it showed up as the single largest cost in streaming.

2.1 has its own parser, written against "Interpreting an event stream" in the HTML standard. It remembers how far it has already searched and only looks at new bytes, so every byte gets searched once. It handles the corner cases the standard spells out: CR, LF, and CRLF line endings (including a CR at the end of one read and the LF at the start of the next), a byte order mark, comments, and pieces that split a UTF-8 character in half.

Before it replaced the gem, it had to produce the same events on all 192 stream bodies recorded in RubyLLM's test suite, fed whole and split many different ways. 116 ms became 2.0 ms, and RubyLLM has one less runtime dependency.

## Text That Copied Itself on Every Delta

The parser wasn't the only thing doing too much per chunk. Anthropic streaming rebuilds each content block so it can be replayed in the next request, and it grew the block's text with `text + delta`. That allocates a new string and copies everything received so far, on every delta. Bedrock's reasoning and OpenRouter's reasoning details did the same with `+=`. A long response paid for itself many times over.

The fix is to append in place with `<<`.

The other per-chunk waste was cost tracking. The usage tracker refreshed the attempt's token counts on every chunk, and recomputed its cost each time, a cost nobody read before the stream ended. Cost is now computed when someone asks for it.

All together, streaming 500 text deltas from Anthropic went from 9.8 ms to 4.1 ms.

## Perplexity's Repeated Citations

Perplexity sends the full citation list on every chunk. RubyLLM deduplicated them with `Array#include?`, which compares each incoming citation against every citation kept so far, and each comparison built the attribute hashes of both citations. Five hundred chunks with twenty sources each turns into a lot of hashes that exist only to be compared and thrown away.

2.1 keeps a hash of the citations it has already seen and reads each incoming one once. 137 ms became 17 ms.

## Replies That Kept Their Requests

`message.raw` gives you the provider's raw response, which is a Faraday response. A Faraday response remembers its request, including the request body. For a chat, the request body is the whole serialized conversation up to that point.

So every reply held a copy of the history that came before it. Turn 40 kept 39 turns of history. Turn 39 kept 38. Put a 256 KB image in the first message, encoded into every one of those request bodies, and the chat's memory grew quadratically with its length. Streamed replies were worse: they also kept the streaming callback, whose closure held the payload Hash the body was built from.

2.1 lets go of both when a call returns. Status, headers, and the response body stay. A streamed 40-turn chat with a 256 KB image went from keeping 28 MB to keeping 0.48 MB.

This is the one change in this post you might notice: `response.raw.env.request_body` is now `nil`. If you were reading requests that way, read them from the chat instead, with `chat.render` or `chat.before_request { |payload| ... }`. The [upgrade guide](https://rubyllm.com/upgrading/#read-requests-before-they-are-sent) has the details.

## Parsing Twice, Resolving Two Hundred Times

Two smaller ones, both about doing work twice.

RubyLLM's error middleware asked the provider for an error message on every response, including successful ones, and threw the answer away for anything that wasn't an error. Getting the error message means parsing the body as JSON. So every successful response was parsed once to look for an error that wasn't there, and again for real. That's cheap for a short reply and not cheap for 100 embeddings in a 2.4 MB response, which went from 4.5 ms to 2.2 ms now that successful responses skip the first parse.

And a chat preprocessed its history one message at a time, resolving which protocol to speak for every message: the configured override, the provider's routing, a new protocol instance. A request now picks its protocol once. Bedrock also used to serialize each payload to sign it, then hand the Hash to Faraday to serialize again; now it sends the bytes it signed. On a Bedrock chat with 200 messages of history, asking again went from 2.9 ms to 0.40 ms.

Separately, Filipe Kalicki made model lookups use an index instead of scanning the whole registry (#981).

## Connections That Were Never Reused

This is the one with the biggest effect across a real network, and the one where you need to opt in.

In 2.0, every call built a new provider, and every provider opened its own Faraday connection. Even if you'd configured an adapter that keeps connections alive, there was nothing to keep alive: the next call made a new connection anyway, and paid a fresh TCP and TLS handshake.

2.1 shares connections across calls, threads, and fibers in a process. There's one connection for each combination of settings that actually changes the connection: provider, API base, adapter, timeout, proxy, logger, and retry options. Credentials travel with each request instead, so tenants with their own API keys share connections too. A forked child, like a Puma worker, opens its own instead of reusing sockets its parent still holds.

The default `:net_http` adapter still opens a connection per request, so pick one that doesn't:

```ruby
# Gemfile
gem "faraday-net_http_persistent"
```

```ruby
require "faraday/net_http_persistent"

RubyLLM.configure do |config|
  config.faraday_adapter = :net_http_persistent
end
```

Twenty calls to a local HTTPS server took one handshake instead of twenty, and 0.4 ms each instead of 2.1 ms. That's on loopback, where a handshake only costs CPU. Across a real network, every handshake you skip also skips its round trips to the provider.

`:net_http_persistent` keeps a pool that threads draw from, which is what you want on Puma and Sidekiq. On Falcon, or with fiber workers, use `:async_http` from `async-http-faraday`. It keeps connections open for as long as the Async reactor that opened them runs. If you're wondering why that's the setup I'd pick for LLM work, I wrote about [why async Ruby is the future](/async-ruby-is-the-future/) and [what Ruby concurrency actually does](/ruby-concurrency-what-actually-happens/). Thousands of mostly-idle streaming conversations on one reactor, sharing warm connections, is the workload fibers were made for.

## Things That Happened Once Per Thread

Two more "every call starts from scratch" problems.

Vertex AI calls each built their own Google credentials, so each call fetched a fresh OAuth token before its actual request. Now credentials are shared per service account key and scope, with a lock so that when a token expires one caller refreshes it while the others wait. Twenty calls, one token request instead of twenty.

The model registry loads lazily, on first use. When several threads reached it at once, each one read and built the whole registry, and the last one to finish replaced the others. That was slow, and a little wrong: a thread could keep using a registry `RubyLLM.models` no longer returned. It now loads once, under a lock, and reads after that take no lock. Eight threads went from 273 ms to 32 ms.

## Rails, Where the Database Was Doing Extra Work

Rebuilding a persisted chat preloaded its messages' usages, tool calls, and attachments, then read them through association readers, and each reader built a proxy and evaluated its scope for rows already in memory. Reading the preloaded rows directly took a 100-message chat from 11.4 ms to 6.8 ms.

Apps that predate Rails' `automatic_scope_inversing` default had it worse: each preloaded usage loaded its message again. RubyLLM now declares the inverses itself, and the same chat went from 58 queries to 8.

Loading a chat also downloaded every stored attachment from Active Storage, whether or not a request followed. Checking `awaiting_approval?` on a chat with ten 1 MB images meant ten downloads to answer a yes-or-no question. Files now download when a request actually sends them.

The last Rails win needs the 2.1 upgrade (`bin/rails generate ruby_llm:upgrade`). Large files get uploaded to the provider, and 2.0 only remembered that upload in memory. A chat loaded in a new process, like the next background job, downloaded the file from storage and uploaded it to the provider all over again. 2.1 records provider uploads in a table and reuses them. Five turns of a chat with a 30 MB PDF, each in a new process, uploaded 150 MB with 2.0. With 2.1, nothing.

## Check My Numbers

The benchmarks live in the repo and need no API keys and no network: providers answer from a canned adapter, a loopback HTTPS server that counts handshakes, or a fake token endpoint. Clone RubyLLM and compare any version with your checkout:

```sh
bundle exec rake "benchmark:compare[v2.0.0]"
bundle exec rake "benchmark:compare[v2.0.0,streaming]"
```

It runs the same scripts against both versions, alternating between them so a noisy machine affects both. Your times will differ from mine, but the counts (queries, downloads, uploads, handshakes) should match.

They also guard against regressions, since every number in this post can be measured again.

The [connection guide](https://rubyllm.com/configuration-connection/#connection-reuse) covers adapters in detail, and [What's New in 2.1](https://rubyllm.com/whats-new-in-2-1/) has everything else in the release.
