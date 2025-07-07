---
layout: post
title: "Async Ruby is the Future (of LLM Communication)"
date: 2025-07-14
description: "How Ruby's async ecosystem transforms resource-intensive LLM applications into efficient, scalable systems -- without rewriting your codebase."
tags: [Ruby, Async, LLM, AI, Rails, Concurrency, Performance, Falcon]
image: /images/async-ruby-llm.png
---

After a decade as an ML engineer immersed in Python's async ecosystem, returning to Ruby felt like stepping back in time. Where was the async revolution? Why was everyone still using threads for everything? SolidQueue, Sidekiq, GoodJob -- all thread-based. Even the newer solutions defaulted to the same concurrency model.

Coming from Python, where the entire community had reorganized around `asyncio`, this seemed bizarre. FastAPI replaced Flask. Every library spawned an async twin. The transformation was total and necessary.

Then I built [RubyLLM](https://github.com/crmne/ruby_llm) and discovered something that changed everything: _LLM communication is async Ruby's killer app_. The unique demands of streaming AI responses -- long-lived connections, token-by-token delivery, thousands of concurrent conversations -- expose exactly why async matters.

But here's the plot twist: once I understood Ruby's approach to async, I realized it's actually *superior* to Python's. While Python forced everyone to rewrite their entire stack, Ruby quietly built something better. Your existing code just works. No syntax changes. No library migrations. Just better performance when you need it.

The async ecosystem that Samuel Williams and others have been building for years suddenly makes perfect sense. We just needed the right use case to see it.

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
- Can be interrupted mid-execution
- Blocks individually on I/O operations
- Requires 8MB of virtual memory for its stack
- Needs its own resources (like database connections)

#### Fibers: Cooperative Concurrency

With fibers, switching is voluntary -- they only yield at I/O boundaries:

```ruby
# Fibers yield control cooperatively
Async do
  fibers = 10.times.map do |i|
    Async do
      expensive_calculation(i)  # Runs to completion
      fetch_from_api(i)        # Yields here, other fibers run
      process_result(i)        # Continues after I/O completes
    end
  end
end
```

Each fiber:
- Schedules itself by yielding during I/O
- Never gets interrupted mid-calculation
- Uses only 24KB of memory (300x smaller than threads!)
- Shares resources through the event loop

### Ruby's GVL: Why Fibers Make Even More Sense

Ruby's Global VM Lock (GVL) means only one thread can execute Ruby code at a time. This creates an interesting dynamic:

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

But here's the thing: if threads only help with I/O anyway, why pay their overhead?

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

Let's recap why fibers are so much more efficient for I/O-heavy workloads:

1. **Tiny Memory Footprint**: 24KB vs 8MB per concurrent operation (300x smaller)
2. **Efficient Scheduling**: No kernel involvement, no preemption overhead
3. **I/O Multiplexing**: One thread monitors thousands of I/O operations
4. **GVL-Friendly**: Since the GVL limits CPU parallelism anyway, cooperative concurrency is ideal
5. **Resource Sharing**: Database connections, memory pools, etc. are naturally shared

The efficiency isn't just theoretical. With threads, your costs scale linearly -- 1000 concurrent operations need 1000 threads (8GB of virtual memory). With fibers, the same load uses one thread and 24MB.

### Why This Matters for LLM Applications

LLM streaming creates the perfect conditions where all these advantages compound:

1. **Long-lived connections**: Each conversation holds resources for minutes
2. **Pure I/O workload**: 99%+ time spent waiting for tokens
3. **Massive concurrency needs**: Modern apps handle thousands of simultaneous chats
4. **Real-time requirements**: Low latency expectations despite high concurrency

With traditional threading, you hit a wall. Each LLM conversation holds a thread (and its 8MB stack, database connection, etc.) hostage for minutes while doing almost nothing. It's like hiring a full-time employee to watch a phone that rings once an hour.

Fibers flip the equation. One thread efficiently multiplexes thousands of LLM streams, switching between them only when tokens arrive. The same server that chokes on 100 concurrent threads can handle 10,000 concurrent fibers.

## Ruby's Async Ecosystem: The Plot Twist Python Didn't See Coming

Here's what makes Ruby's async special: while Python fractured its ecosystem with incompatible libraries and forced syntax changes (given the requirement to always use `async`/`await` to benefit from `asyncio`), Ruby took a different path. Samuel Williams, as a Ruby core committer who implemented the Fiber Scheduler interface, understood something fundamental -- async should enhance Ruby, not replace it.

The result? As long as your underlying libraries are Fiber-aware, you can simply wrap your code in Fibers or Async tasks and it will be magically faster!

### The Foundation: The `async` Gem

The beauty of Ruby's async lies in its transparency:

```ruby
require 'async'
require 'net/http'

# This code handles 1000 concurrent requests
# Using ONE thread and minimal memory
Async do
  responses = 1000.times.map do |i|
    Async do
      uri = URI("https://api.openai.com/v1/chat/completions")
      # Net::HTTP is fiber-aware in Ruby 3.0+
      # It automatically yields during I/O
      response = Net::HTTP.post(uri, data.to_json, headers)
      JSON.parse(response.body)
    end
  end.map(&:wait)

  # All 1000 requests complete concurrently
  process_responses(responses)
end
```

No callbacks. No promises. No `async`/`await` keywords. Just Ruby code that scales.

## Migrating your Rails app to the Async ecosystem

The remarkable thing about Ruby's async is how little changes. Your business logic remains untouched.

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

The impact is dramatic. In production LLM applications:

- **Concurrency**: Handle many more concurrent conversations with the same hardware
- **Memory usage**: Dramatically reduced due to fiber efficiency
- **Response latency**: Lower and more predictable without thread scheduling overhead
- **Infrastructure costs**: Significantly reduced server requirements

The difference is especially pronounced for LLM workloads where connections are long-lived and mostly idle, waiting for the next token to stream.

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

## A New Chapter for Ruby

After years in Python's async world, I've seen what happens when a language forces a syntax change to access the benefits of async concurrency on its community. Libraries fragment. Codebases split. Developers struggle with new syntax and concepts.

Ruby chose a different path -- and it's the right one.

We're witnessing Ruby's next evolution. Not through breaking changes or ecosystem splits, but through thoughtful additions that make our existing code better. The async ecosystem that seemed unnecessary when compared to traditional threading suddenly becomes essential when you hit the right use case.

LLM applications are that use case. The combination of long-lived connections, streaming responses, and massive concurrency creates the perfect storm where async's benefits become undeniable.

Samuel Williams and the async community have given us incredible tools. Unlike Python, you don't have to rewrite everything to use it.

For those building the next generation of AI-powered applications, async Ruby isn't just an option -- it's a competitive advantage. Lower costs, better performance, simpler operations, and you keep your existing codebase.

The future is concurrent. The future is streaming. The future is async.

And in Ruby, that future works with the code you already have.

---

*RubyLLM powers [Chat with Work](https://chatwitwork.com) in production with thousands of concurrent AI conversations. Want elegant AI integration in Ruby? Check out [RubyLLM](https://rubyllm.com).*

**Join the conversation:** I'll be speaking about async Ruby and AI at [EuRuKo 2025](https://2025.euruko.org/), [San Francisco Ruby Conference 2025](https://sfruby.com/), and [RubyConf Thailand 2026](https://rubyconfth.com/). Let's build the future together.