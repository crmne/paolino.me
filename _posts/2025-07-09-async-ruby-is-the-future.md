---
layout: post
title: "Async Ruby is the Future of AI Apps (And It's Already Here)"
date: 2025-07-09
description: "How Ruby's async ecosystem transforms resource-intensive LLM applications into efficient, scalable systems - without rewriting your codebase."
tags: [Ruby, Async, LLM, AI, Rails, Concurrency, Performance, Falcon]
image: /images/async.webp
---

After a decade as an ML engineer/scientist immersed in Python's async ecosystem, returning to Ruby felt like stepping back in time. Where was the async revolution? Why was everyone still using threads for everything? SolidQueue, Sidekiq, GoodJob -- all thread-based. Even newer solutions defaulted to the same concurrency model.

Coming from Python, where the entire community had reorganized around `asyncio`, this seemed bizarre. FastAPI replaced Flask. Every library spawned an async twin. The transformation was total and necessary.

Then, building [RubyLLM][] and [Chat with Work][], I noticed that _LLM communication is async Ruby's killer app_. The unique demands of streaming AI responses -- long-lived connections, token-by-token delivery, thousands of concurrent conversations -- expose exactly why async matters.

Here's the exciting bit: once I understood Ruby's approach to async, I realized it's actually *superior* to Python's. While Python forced everyone to rewrite their entire stack, Ruby quietly built something better. Your existing code just works. No syntax changes. No library migrations. Just better performance when you need it.

The async ecosystem that [Samuel Williams][] and others have been building for years suddenly makes perfect sense. We just needed the right use case to see it.

## Why LLM Communication Breaks Everything

LLM applications create a perfect storm of challenges that expose every weakness in thread-based concurrency:

### 1. Slot Starvation

Configure any thread-based job queue with 25 workers:

```ruby
class StreamAIResponseJob < ApplicationJob
  def perform(chat, message)
    # This job occupies 1 of your 25 slots...
    chat.ask(message) do |chunk|
      # ...for the ENTIRE streaming duration (30-60 seconds)
      broadcast_chunk(chunk)
      # Thread is 99% idle, just waiting for tokens
    end
    # Slot only freed here, after full response
  end
end
```

Your 26th user? They're waiting in line. Not because your server is busy, but because all your workers are occupied by jobs waiting for tokens.

### 2. Resource Multiplication

Each background job worker thread needs its own:
- Database connection (25 workers = 25 connections minimum)
- Stack memory allocation
- OS thread management overhead

For 1000 concurrent conversations using traditional job queues like SolidQueue or Sidekiq, you'd need 1000 worker threads. Each worker thread holds its database connection for the entire job duration. That's 1000 database connections for threads that are 99% idle, waiting for streaming tokens.

### 3. Performance Overhead

Real benchmarks show[^1]:
- Creating a thread: ~80μs
- Thread context switch: ~1.3μs
- Maximum throughput: ~5,000 requests/second

When you're handling thousands of streaming connections, these microseconds add up to real latency.

### 4. Scalability Challenges

Try creating 10,000 threads and the OS scheduler starts to struggle. The overhead becomes crushing. Yet modern AI apps need to handle thousands of concurrent conversations.

These aren't separate issues -- they're all symptoms of the same architectural mismatch. LLM communication is fundamentally different from traditional background jobs.

[^1]: [Samuel Williams][]' [fiber-vs-thread performance comparison](https://github.com/socketry/performance/tree/adfd780c6b4842b9534edfa15e383e5dfd4b4137/fiber-vs-thread)

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
- **20x faster allocation**: Creating a fiber takes ~3μs vs ~80μs for a thread
- **10x faster context switching**: Fiber switches in ~0.1μs vs ~1.3μs for threads
- **15x higher throughput**: ~80,000 vs ~5,000 requests/second

But the real advantage is **scalability**:

1. **Fewer OS Resources**: Fibers are managed in userspace, avoiding kernel overhead
2. **Efficient Scheduling**: No kernel involvement means less overhead
3. **I/O Multiplexing**: One thread monitors thousands of I/O operations via `epoll`/`kqueue`/`io_uring`
4. **GVL-Friendly**: Cooperative scheduling works naturally with Ruby's concurrency model
5. **Resource Sharing**: Database connections and memory pools are naturally shared

While memory usage between fibers and threads is comparable, fibers don't depend on OS resources. You can create vastly more fibers than threads, switch between them faster, and manage them more efficiently while monitoring thousands of connections -- all from userspace.

## How Async Solves Every LLM Challenge

Remember those four problems? Here's how async addresses each one:

1. **No More Slot Starvation**: Fibers are created on-demand and destroyed immediately. No fixed worker pools.
2. **Shared Resources**: One process with a few pooled database connections can handle thousands of conversations.
3. **Improved Performance**: 20x faster to create, 10x faster to switch, 15x less scheduling overhead (synthetic upper bound).
4. **Massively Improved Scalability**: 10,000+ concurrent fibers? No problem. The OS doesn't even know they exist.

## Ruby's Async Ecosystem

The beauty of Ruby's [async][] lies in its transparency. Unlike Python's requirement to use `async`/`await` everywhere, Ruby code just works:

### The Foundation: The [async][] Gem

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

### Why RubyLLM Just Works™

Here's the thing that made me smile when I discovered it: [RubyLLM][] gets async performance *for free*. No special RubyLLM-async version needed. No code changes to the library. No configuration. Nothing.

Why? Because RubyLLM uses `Net::HTTP` under the hood. When you wrap RubyLLM calls in an Async block, `Net::HTTP` automatically yields during network I/O, allowing thousands of concurrent LLM conversations to happen on a single thread.

```ruby
# This is all you need for concurrent LLM calls
Async do
  10.times.map do
    Async do
      # RubyLLM automatically becomes non-blocking
      # because Net::HTTP knows how to yield to fibers
      message = RubyLLM.chat.ask "Explain quantum computing"
      puts message.content
    end
  end.map(&:wait)
end
```

This is Ruby at its best. Libraries that follow conventions get superpowers without even trying. It just works because it was built on solid foundations.

Check out [RubyLLM's Scale with Async guide](https://rubyllm.com/guides/async) to learn more.

### The Rest of the Ecosystem

- **[Falcon][]**: Multi-process, multi-fiber web server built for streaming
- **[async-job][]**: Background job processing using fibers
- **[async-cable][]**: ActionCable replacement with fiber-based concurrency
- **[async-http][]**: Full-featured HTTP client with streaming support

... and many more available from [Socketry](https://github.com/orgs/socketry/repositories).

## Migrate your Rails app to Async

The migration requires almost no code changes:

### Step 1: Update Your Gemfile

```ruby
# Gemfile
# Comment out thread-based gems
# gem "puma"
# gem "sidekiq" / "good_job" / "solid_queue"
# gem "solid_cable"

# Add async gems
gem "falcon"
gem "async-job-adapter-active_job"
gem "async-cable"
```

### Step 2: Configure Your Application

```ruby
# config/application.rb
require "async/cable"

# config/initializers/async_job.rb
require 'async/job/processor/inline'

Rails.application.configure do
  config.async_job.define_queue "default" do
    dequeue Async::Job::Processor::Inline
  end
  
  config.active_job.queue_adapter = :async_job
end
```

### Step 3: There's No Step 3!

Your existing jobs work unchanged. Your channels don't need updates.

Just deploy with Falcon and watch. You'll get more performance, more capacity, and better response times.

#### Note on Puma

The above configuration works out of the box with Falcon. If you're using Puma, you'll need additional setup for concurrent job processing. See the [RubyLLM Async Guide](https://rubyllm.com/guides/async#note-on-puma) for Puma configuration details.

### Mixing Job Adapters: Best of Both Worlds

You don't have to go all-in. Use async-job only for LLM operations while keeping your existing job processor for everything else:

```ruby
# Keep your existing adapter as default
config.active_job.queue_adapter = :solid_queue  # or :sidekiq, :good_job, etc.

# Base class for all LLM jobs
class LLMJob < ApplicationJob
  self.queue_adapter = :async_job
end

# LLM jobs inherit the async adapter
class ChatResponseJob < LLMJob
  def perform(conversation_id, message)
    # Runs with async-job - perfect for streaming
    response = RubyLLM.chat.ask(message)
    # ...
  end
end

# Regular jobs use your default adapter
class ImageProcessingJob < ApplicationJob
  def perform(image_id)
    # Runs with solid_queue - better for CPU work
    # ...
  end
end
```

This approach lets you optimize each job type for its workload without disrupting your existing infrastructure.

## When to Use What

Let's be practical -- async isn't always the answer:

**Use threads for:**
- CPU-intensive work
- Tasks needing true isolation
- Legacy C extensions that aren't fiber-safe

**Use async for:**
- I/O-bound operations
- API calls
- WebSockets, SSE, and other forms of streaming
- LLM applications

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

*[RubyLLM][] powers [Chat with Work][] in production with thousands of concurrent AI conversations using [async][]. Want elegant AI integration in Ruby? Check out [RubyLLM][].*

*Special thanks to [Samuel Williams][] for reviewing this post and providing the [fiber-vs-thread benchmarks](https://github.com/socketry/performance/tree/adfd780c6b4842b9534edfa15e383e5dfd4b4137/fiber-vs-thread) that substantiate these performance claims.*

**Join the conversation:** I'll be speaking about async Ruby and AI at [EuRuKo 2025](https://2025.euruko.org/), [San Francisco Ruby Conference 2025](https://sfruby.com/), and [RubyConf Thailand 2026](https://rubyconfth.com/). Let's build the future together.

[RubyLLM]: https://rubyllm.com
[Chat with Work]: https://chatwithwork.com
[Samuel Williams]: https://github.com/ioquatix
[async]: https://github.com/socketry/async
[Falcon]: https://github.com/socketry/falcon
[async-job]: https://github.com/socketry/async-job
[async-http]: https://github.com/socketry/async-http
[async-cable]: https://github.com/socketry/async-cable