---
layout: post
title: "Async Ruby is the Future (of LLM Communication)"
date: 2025-07-08
description: "How Ruby's async ecosystem transforms resource-intensive LLM applications into efficient, scalable systems -- without rewriting your codebase."
tags: [Ruby, Async, LLM, AI, Rails, Concurrency, Performance, Falcon]
image: /images/async.webp
---

After a decade as an ML engineer immersed in Python's async ecosystem, returning to Ruby felt like stepping back in time. Where was the async revolution? Why was everyone still using threads for everything? SolidQueue, Sidekiq, GoodJob -- all thread-based. Even newer solutions defaulted to the same concurrency model.

Coming from Python, where the entire community had reorganized around `asyncio`, this seemed bizarre. FastAPI replaced Flask. Every library spawned an async twin. The transformation was total and necessary.

Then, building [RubyLLM][] and [Chat with Work][], I noticed that _LLM communication is async Ruby's killer app_. The unique demands of streaming AI responses -- long-lived connections, token-by-token delivery, thousands of concurrent conversations -- expose exactly why async matters.

Here's when it got exciting: once I understood Ruby's approach to async, I realized it's actually *superior* to Python's. While Python forced everyone to rewrite their entire stack, Ruby quietly built something better. Your existing code just works. No syntax changes. No library migrations. Just better performance when you need it.

The async ecosystem that [Samuel Williams][] and others have been building for years suddenly makes perfect sense. We just needed the right use case to see it.

## Understanding Concurrency: Threads vs Async

To understand why LLM applications are async's perfect use case -- and why Ruby's implementation is so elegant -- we need to build up from first principles.

### The Hierarchy: Processes, Threads, and Fibers

Think of your computer as an office building:

- **Processes** are like separate offices -- each with its own locked door, furniture, and files. They can't see into each other's spaces (memory isolation).
- **Threads** are like workers sharing the same office -- they can access the same filing cabinets (shared memory) but need to coordinate to avoid collisions.
- **Fibers** are like multiple tasks juggled by one worker at their desk -- switching between them manually when waiting for something (like a phone call).

### Scheduling: The Core Difference

The fundamental question in concurrency is: who decides when to switch between tasks?

#### Threads: Preemptive Multitasking

With threads, the operating system is the boss. It forcibly interrupts running threads to give others a turn:

```ruby
# You start threads, but the OS controls them
threads = 10.times.map do |i|
  Thread.new do
    # This might be interrupted at ANY point
    expensive_calculation(i)
    fetch_from_api(i)  # Each thread blocks individually here
    process_result(i)
  end
end
```

Each thread:
- Gets scheduled by the OS kernel
- Can be interrupted mid-execution (in Ruby, after 100ms)
- Blocks individually on I/O operations
- Requires OS resources and kernel data structures
- Needs its own resources (like database connections)

#### Fibers: Cooperative Concurrency

With fibers, switching is voluntary -- they only yield at I/O boundaries:

```ruby
# Fibers yield control cooperatively
Async do
  fibers = 10.times.map do |i|
    Async do
      expensive_calculation(i)  # Runs to completion
      fetch_from_api(i)         # Yields here, other fibers run
      process_result(i)         # Continues after I/O completes
    end
  end
end
```

Each fiber:
- Schedules itself by yielding during I/O
- Never gets interrupted mid-calculation
- Managed entirely in userspace (no kernel involvement)
- Shares resources through the event loop

### Ruby's GVL: Why Fibers Make Even More Sense

Ruby's Global VM Lock (GVL) means only one thread can execute Ruby code at a time. Threads are preempted after a 100ms time quantum.

This creates an interesting dynamic:

```ruby
# CPU work: Threads don't help much due to GVL
threads = 4.times.map do
  Thread.new { calculate_fibonacci(40) }
end
# Takes about the same time as sequential execution!

# I/O work: Threads do parallelize (GVL released during I/O)
threads = 4.times.map do
  Thread.new { Net::HTTP.get(uri) }
end
# Takes 1/4 the time of sequential execution
```

But here's the thing: if threads only help with I/O anyway, _why pay their overhead_?

### The I/O Multiplexing Advantage

This is where fibers truly shine. Threads use a "one thread, one I/O operation" model:

```ruby
# Traditional threading approach
thread1 = Thread.new { socket1.read }  # Blocks this thread
thread2 = Thread.new { socket2.read }  # Blocks this thread
thread3 = Thread.new { socket3.read }  # Blocks this thread
# Need 3 threads for 3 concurrent I/O operations
```

Fibers use I/O multiplexing -- one thread monitors *all* I/O:

```ruby
# Async's approach (simplified)
Async do
  # One thread, many I/O operations
  task1 = Async { socket1.read }  # Registers with selector
  task2 = Async { socket2.read }  # Registers with selector
  task3 = Async { socket3.read }  # Registers with selector

  # Event loop uses epoll/kqueue to monitor ALL sockets
  # Resumes fibers as data becomes available
end
```

The kernel (via `epoll`, `kqueue`, or `io_uring`) can monitor thousands of file descriptors with a single system call. No thread-per-connection needed.

### Why Fibers Win: The Complete Picture

Let's look at real benchmark data comparing fibers to threads[^1]:

**Performance Advantages (Ruby 3.4 data)**:
- **18x faster allocation**: Creating a fiber takes ~4.7μs vs ~84μs for a thread
- **17x faster context switching**: Fiber switches in ~0.14μs vs ~2.4μs for threads
- **7.4 million switches/second** with fibers vs 425,000 with threads

But the real advantage is **scalability**:

1. **OS Resource Limits**: Creating 10,000 threads can fail on macOS due to system limits, while 10,000 fibers works effortlessly
2. **Efficient Scheduling**: No kernel involvement means less overhead
3. **I/O Multiplexing**: One thread monitors thousands of I/O operations via epoll/kqueue
4. **GVL-Friendly**: Cooperative scheduling works naturally with Ruby's concurrency model
5. **Resource Sharing**: Database connections and memory pools are naturally shared

While memory usage between fibers and threads is comparable, fibers don't depend on OS resources. You can create vastly more fibers than threads, switch between them faster, and manage them more efficiently while monitoring thousands of connections -- all from userspace.

[^1]: Benchmark data from [Samuel Williams][]' [fiber-vs-thread performance comparison](https://github.com/socketry/performance/tree/main/fiber-vs-thread)

### Why This Matters for LLM Applications

LLM streaming creates the perfect conditions where all these advantages compound:

1. **Long-lived connections**: Each conversation holds resources for minutes
2. **Pure I/O workload**: 99%+ time spent waiting for tokens
3. **Massive concurrency needs**: Modern apps handle thousands of simultaneous chats
4. **Real-time requirements**: Low latency expectations despite high concurrency

With traditional threading, you hit OS limits quickly. Need to handle 10,000 concurrent LLM streams? Good luck creating 10,000 threads -- the OS will likely refuse if not configured correctly. Even if it works, you're paying for expensive context switches millions of times per second.

Fibers flip the equation. One thread efficiently multiplexes thousands of LLM streams, switching between them in nanoseconds only when tokens arrive.

## Ruby's Async Ecosystem

Here's what makes Ruby's [async][] special: while Python fractured its ecosystem with incompatible libraries and forced syntax changes given the requirement to use `async`/`await` to benefit from `asyncio`, Ruby took a different path. [Samuel Williams][], as a Ruby core committer who implemented the Fiber Scheduler interface, understood something fundamental -- async should enhance Ruby, not replace it.

The result? Most Ruby code works with async out of the box. If your code is either synchronous (most libraries) or thread-safe, it'll work seamlessly in an async environment. No special async versions needed!

### The Foundation: The [async][] Gem

The beauty of Ruby's [async][] lies in its transparency:

```ruby
require 'async'
require 'net/http'

# This code handles 1000 concurrent requests
# Using ONE thread and minimal memory
Async do
  responses = 1000.times.map do |i|
    Async do
      uri = URI("https://api.openai.com/v1/chat/completions")
      # Net::HTTP automatically yields during I/O
      response = Net::HTTP.post(uri, data.to_json, headers)
      JSON.parse(response.body)
    end
  end.map(&:wait)

  # All 1000 requests complete concurrently
  process_responses(responses)
end
```

No callbacks. No promises. No async/await keywords. Just Ruby code that scales.

### The Rest of the Ecosystem

- **[Falcon][]**: Multi-process, multi-fiber web server built for streaming
- **[async-job][]**: Background job processing using fibers
- **[async-cable][]**: ActionCable replacement with fiber-based concurrency
- **[async-http][]**: Full-featured HTTP client with streaming support

... and many more available from [Socketry](https://github.com/orgs/socketry/repositories)

## Migrating to Async: A Pragmatic Approach

The remarkable thing about Ruby's [async][] is how little changes. Your business logic remains untouched.

### Step 1: Update Dependencies

```ruby
# Gemfile

# Comment out the thread-based ecosystem
# gem "puma"
# gem "solid_queue"
# gem "solid_cable"

# Add the async ecosystem
gem "falcon"
gem "async-job-adapter-active_job"
gem "async-cable"
```

### Step 2: Configure Rails

```ruby
# config/application.rb
require "async/cable" if defined?(Async::Cable)

# config/environments/production.rb
config.active_job.queue_adapter = :async_job
```

### Step 3: Your Existing Code Just Works

```ruby
# This job runs unchanged in the async environment
class StreamAIResponseJob < ApplicationJob
  def perform(conversation, message)
    # RubyLLM automatically uses async I/O when available
    conversation.chat(message) do |chunk|
      # Broadcasting works seamlessly with async-cable
      ConversationChannel.broadcast_to(
        conversation,
        { content: chunk.content }
      )
    end
  end
end
```

No special base classes. No syntax changes. Your Rails app gains async superpowers transparently.

## Real-World Performance

The impact is dramatic. Based on benchmarks and production experience:

- **Allocation Performance**: Fibers are 5-18x faster to create than threads
- **Context Switching**: Fibers switch 3-17x faster than threads
- **Scalability**: Handle 10-100x more concurrent operations before hitting system limits
- **Latency**: More predictable performance without preemptive scheduling overhead

For LLM workloads specifically, where connections are long-lived and mostly idle waiting for tokens, the advantages multiply. A single process using fibers can handle the load that would require multiple servers using threads.

## When to Choose What

Let's be clear: async isn't always the answer. Different workloads benefit from different concurrency models:

#### Choose Threads When:
- CPU-intensive processing dominates
- Tasks require true isolation
- You need preemptive scheduling guarantees
- Working with non-fiber-aware C extensions

#### Choose Async When:
- I/O operations dominate (APIs, databases, file systems)
- Handling many concurrent connections
- Building real-time features
- Streaming data or Server-Sent Events

**LLM applications are the perfect async use case**: massive I/O wait times, streaming responses, and thousands of concurrent conversations.

## The Path Forward

Ruby's async ecosystem represents a fundamental shift in how we build concurrent applications. Not through revolutionary syntax changes or ecosystem fragmentation, but through careful evolution that preserves what makes Ruby great.

For LLM applications specifically, the choice is becoming clear. The combination of long-lived connections, streaming responses, and massive concurrency demands an architecture built for these patterns.

The tools are mature. The performance gains are real. The migration path is smooth.

### Getting Started in 30 Minutes

1. **Add the gems**: `falcon`, `async-job-adapter-active_job`, `async-cable`
2. **Configure Rails**: Add one line to enable async-cable
3. **Deploy**: Falcon automatically replaces Puma
4. **Monitor**: Watch your resource usage plummet

Your existing ActiveJob code continues working. Your ActionCable channels don't change. You just get better performance.

## A New Chapter for Ruby

After years in Python's async world, I've seen what happens when a language forces a syntax change to access the benefits of async concurrency on its community. Libraries fragment. Codebases split. Developers struggle with new syntax and concepts.

Ruby chose a different path -- and it's the right one.

We're witnessing Ruby's next evolution. Not through breaking changes or ecosystem splits, but through thoughtful additions that make our existing code better. The async ecosystem that seemed unnecessary when compared to traditional threading suddenly becomes essential when you hit the right use case.

LLM applications are that use case. The combination of long-lived connections, streaming responses, and massive concurrency creates the perfect storm where async's benefits become undeniable.

[Samuel Williams][] and the [async][] community have given us incredible tools. Unlike Python, you don't have to rewrite everything to use it.

For those building the next generation of AI-powered applications, [async][] Ruby isn't just an option -- it's a competitive advantage. Lower costs, better performance, simpler operations, and you keep your existing codebase.

The future is concurrent. The future is streaming. The future is [async][].

And in Ruby, that future works with the code you already have.

---

*[RubyLLM][] powers [Chat with Work][] in production with thousands of concurrent AI conversations. Want elegant AI integration in Ruby? Check out [RubyLLM][].*

*Special thanks to [Samuel Williams][] for reviewing this post and providing the [fiber-vs-thread benchmarks](https://github.com/socketry/performance/tree/main/fiber-vs-thread) that substantiate these performance claims.*

**Join the conversation:** I'll be speaking about async Ruby and AI at [EuRuKo 2025](https://2025.euruko.org/), [San Francisco Ruby Conference 2025](https://sfruby.com/), and [RubyConf Thailand 2026](https://rubyconfth.com/). Let's build the future together.

[RubyLLM]: https://rubyllm.com
[Chat with Work]: https://chatwitwork.com
[Samuel Williams]: https://github.com/ioquatix
[async]: https://github.com/socketry/async
[Falcon]: https://github.com/socketry/falcon
[async-job]: https://github.com/socketry/async-job
[async-http]: https://github.com/socketry/async-http
[async-cable]: https://github.com/socketry/async-cable