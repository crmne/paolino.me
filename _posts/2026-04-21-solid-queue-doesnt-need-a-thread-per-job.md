---
layout: post
title: "Making the Rails Default Job Queue Fiber-Based"
date: 2026-04-21
description: "I tried Async::Job for my LLM apps, hit its limits, and patched Solid Queue to run jobs as fibers instead."
tags: [Ruby, Async, Rails, Solid Queue, Performance, Concurrency, Open Source]
image: /images/solid-queue-async.webp
---
Last year I moved the LLM streaming jobs in [Chat with Work][] to [Async::Job][async-job]. It was fast. Genuinely fast. Fiber-based execution with Redis, thousands of concurrent jobs on a single thread. I was so convinced that I [wrote a whole post][async-article] about why async Ruby is the future for AI apps and recommended it to everyone.

Then I started hitting walls.

Async::Job doesn't persist jobs. They go into Redis and they're gone. [Mission Control][] shows nothing. Background jobs in Rails are already quieter than the rest of your application -- they fail without anyone noticing unless you go looking. Even with Honeybadger catching exceptions, I still want to see the full picture: which jobs are queued, which are running, which failed, what the system looks like right now. Without job persistence, you don't get that.

There's also a design tension around CPU-bound work. Async::Job ties health signaling to the reactor, and for good reason -- it detects event loop stalls. But when a job blocks the reactor, the health check can't fire either. I explored this with [Samuel Williams][] and realized the core issue wasn't the health model. It was that I was trying to make an async-native system tolerate non-async code.

Solid Queue is the default in Rails 8. Every new Rails app ships with it. When someone picks up Rails to build an LLM application and their 25-thread worker pool can only handle 25 concurrent streaming conversations, the answer shouldn't be "swap your entire job backend." It should be "change one line of config."

So I [opened a PR][pr].

## Threads vs fibers, quickly

If you already know this, [skip ahead to the config](#the-switch).

Solid Queue runs each job on its own thread. Each thread needs its own database connection, its own stack memory, and a slot in the OS scheduler. For a job that crunches data for 30 seconds, that's fine -- the thread is busy. For a job that streams an LLM response for 30 seconds but spends 99% of that time waiting for tokens, the thread is just sitting there holding resources.

Fibers are Ruby's lightweight alternative. They're cooperatively scheduled and run entirely in userspace. When a fiber hits I/O -- a network call, a database query, waiting for the next token -- it yields automatically, and another fiber picks up. One thread can run hundreds of fibers concurrently. No OS scheduling overhead, no extra database connections. The [async][] gem makes this transparent: your existing Ruby code yields at I/O boundaries without any syntax changes.

For the full deep dive -- processes, threads, fibers, the GVL, I/O multiplexing -- see [Async Ruby is the Future][async-article].

## The switch

While the PR gets approved, you can point your Gemfile at the branch:

```ruby
# Gemfile
gem "solid_queue", git: "https://github.com/crmne/solid_queue.git", branch: "async-worker-execution-mode"
```

Then one config change:

```yaml
# config/solid_queue.yml
production:
  workers:
    - queues: ["*"]
      # threads: 10
      fibers: 100  # <- that's it
      processes: 2
```

Your jobs don't change. Your queue doesn't change. The worker runs them as fibers instead of threads.

The concurrency model is determined by which key you use: `threads` for thread-based execution, `fibers` for fiber-based. They're mutually exclusive. One more thing in your Rails app:

```ruby
# config/application.rb
config.active_support.isolation_level = :fiber  # required for fibers
```

Multiple fibers sharing a thread need fiber-scoped execution state instead of the default thread-scoped state. The patch validates this at boot and gives you a clear error if it's wrong.

## Under the hood

The core of the patch is `FiberPool`. A single thread runs an [async][] reactor with a semaphore that bounds concurrency to whatever you configured as `fibers`:

```ruby
def start_reactor
  create_thread do
    Async do |task|
      semaphore = Async::Semaphore.new(size, parent: task)
      boot_queue << :ready

      wait_for_executions(semaphore)
      wait_for_inflight_executions
    end
  end
end
```

When a worker claims jobs from the database, it posts them to the pool. The reactor schedules each one as a fiber:

```ruby
def schedule_pending_executions(semaphore)
  while execution = next_pending_execution
    semaphore.async(execution) do |_execution_task, scheduled_execution|
      perform_execution(scheduled_execution)
    end
  end
end
```

Each job runs inside a fiber. When it hits I/O, it yields. The reactor picks up another fiber. One thread juggles hundreds of concurrent jobs, switching between them at I/O boundaries instead of relying on the OS scheduler to preempt them.

CPU-bound work doesn't benefit from this. Fibers don't parallelize computation. But for I/O-bound work, which is most of what job queues process, the execution model fits the workload. And because Solid Queue's supervisor runs on its own process, a CPU-bound fiber just blocks the reactor until it finishes. The supervisor keeps monitoring normally.

## The database connection math

I [wrote about this last year][async-article]:

> For 1000 concurrent conversations using traditional job queues like SolidQueue or Sidekiq, you'd need 1000 worker threads. Each worker thread holds its database connection for the entire job duration. That's 1000 database connections for threads that are 99% idle, waiting for streaming tokens.

That was the theory. Here's the actual math from the patch.

A Solid Queue worker needs database connections for three things: polling for new jobs, sending its heartbeat, and executing jobs. In the threads concurrency model, every thread can query the database concurrently, so each thread needs its own connection. The formula is `threads + 2`: one connection per thread, plus two for the worker's own polling and heartbeat.

In the fiber concurrency model on Rails 7.2+, all fibers run on a single reactor thread. Only one fiber executes at a time. That means fibers can never make concurrent database queries. They share one connection. Active Record on 7.2+ helps here: connections are query-scoped, meaning they're released back to the pool after each query rather than held for the lifetime of the fiber. So the formula is `1 + 2 = 3`: one shared execution connection, plus two for polling and heartbeat.

Same number of concurrent jobs, different concurrency model, very different connection requirements:

| Concurrent jobs | Thread DB pool (per process) | Fiber DB pool (per process) |
|---|---|---|
| 10 | 12 | 3 |
| 25 | 27 | 3 |
| 50 | 52 | 3 |
| 100 | 102 | 3 |
| 200 | 202 | 3 |

Thread scales linearly. Fiber stays flat. Multiply by the number of worker processes and the gap gets dramatic: 6 processes with 50 concurrent jobs means 312 connections for thread mode, 18 for fiber. PostgreSQL's default `max_connections` is 100.

The patch detects your Rails version and calculates the right pool size automatically.

## The benchmarks

I benchmarked four workloads across every combination of concurrency model, concurrency (5 to 100), and process count (1, 2, 6). Each configuration ran 5 times, median reported. Total concurrency was capped at 60 for both modes to keep the comparison fair.

The workloads:

- **Sleep**: 50ms `Kernel.sleep`. Pure cooperative wait. The I/O upper bound.
- **Async HTTP**: HTTP request to a local server with 50ms delay via [Async::HTTP][async-http]. Real fiber-friendly I/O.
- **CPU**: 50,000 SHA256 iterations. Pure computation. The control.
- **RubyLLM Stream**: Actual [RubyLLM][] chat completion through a fake OpenAI SSE endpoint, with token-by-token Turbo Stream broadcasts. 40 tokens at 20ms each. The closest thing to a production AI workload you can benchmark repeatably.

### Results

| Workload | Thread Best | Fiber Best | Best Paired Delta |
|---|---|---|---|
| RubyLLM Stream | 6.25 j/s | 6.68 j/s | **+20.2%** |
| Async HTTP | 432.08 j/s | 512.25 j/s | **+26.0%** |
| Sleep | 447.78 j/s | 507.19 j/s | **+27.2%** |
| CPU | 107.42 j/s | 112.47 j/s | +5.1% |

RubyLLM Stream is the workload that matters. It runs an actual [RubyLLM][] chat completion with streaming, database writes, and Turbo broadcasts per token -- the same thing [Chat with Work][] does in production. Fiber wins every single paired experiment. 9 out of 9.

The CPU row is the control. Fibers don't help computation, and the number confirms it: essentially flat. That's how you know the I/O gains are real and not measurement noise.

The table above shows the best runs. Here's the full picture across all configurations. Some configurations favor threads for synthetic workloads, but the median (black dot) tilts fiber for every I/O workload, and the real RubyLLM Stream scenario always favors fiber:

![Solid Queue fiber over thread throughput ranges across all workloads.](/images/solid-queue-throughput-fiber-vs-thread.png)

## Thread mode hit the wall

The headline benchmarks cap total concurrency at 60 to keep the comparison fair. I wanted to see what happens when you push past that, so I ran a stress suite: 25 to 200 concurrent jobs per worker, with 2 and 6 worker processes.

Remember the database math from earlier: thread mode needs `threads + 2` connections per process, fiber mode needs 3. Here's what that means in practice for thread mode:

| Concurrent jobs | Processes | DB pool (per process) | Total connections | Result |
|---|---|---|---|---|
| 25 | 2 | 27 | 54 | Completed |
| 50 | 2 | 52 | 104 | **Failed** |
| 25 | 6 | 27 | 162 | **Failed** |
| 50 | 6 | 52 | 312 | **Failed** |

PostgreSQL's default `max_connections` is 100. Thread mode at 50 concurrent jobs with just 2 processes already exceeds it. With 6 processes, even 25 concurrent jobs needs 162 connections. Out of every thread configuration I tested, only one survived: the smallest.

Fiber mode needs 3 connections per process regardless of how many concurrent jobs you configure:

| Concurrent jobs | Processes | DB pool (per process) | Total connections | Result |
|---|---|---|---|---|
| 25 | 6 | 3 | 18 | Completed |
| 100 | 6 | 3 | 18 | Completed |
| 200 | 6 | 3 | 18 | Completed |

Every configuration completed. 18 total connections for 200 concurrent jobs across 6 processes. Thread mode needed 54 just to survive at 25 with 2.

Thread mode doesn't scale because it can't. Every thread holds a connection, and database connections are a hard ceiling. Fiber mode scales because fibers share a small pool. You just increase the number.

## One backend, two modes

Fiber mode isn't universally better. CPU-bound jobs get nothing from it. C extensions that aren't fiber-safe won't work. And that's fine -- you don't have to pick one.

As Trevor Turk pointed out in the PR discussion, this is really the key insight: separately configured worker pools. Here's a simplified version of what [Chat with Work][] runs in production:

```yaml
workers:
  - queues: [ chat ]
    fibers: 10
    processes: 2
    polling_interval: 0.1
  - queues: [ turbo ]
    fibers: 10
    processes: 1
    polling_interval: 0.05
  - queues: [ notifications, default, maintenance ]
    fibers: 5
    processes: 1
    polling_interval: 0.2
  - queues: [ cpu ]
    threads: 1
    processes: 1
```

Almost everything uses fibers. LLM streaming, Turbo broadcasts, notifications, maintenance jobs -- all fiber-based. Only the `cpu` queue uses threads, and right now it's just one thread for the occasional heavy extraction. One backend. One deployment. [Mission Control][] shows all of it.

Instead of running Solid Queue and Async::Job side by side -- two processors, two configurations, two sets of things to monitor -- you run one. I moved [Chat with Work][] to this setup, and Brad Gessler has been running it in production too.

Async::Job is actually faster if you compare raw throughput against Redis. It's not close:

![Async::Job over Solid Queue fiber throughput ranges.](/images/solid-queue-throughput-asyncjob-vs-fiber.png)

If you're chasing pure speed and don't need persistence, use Async::Job -- it's great. If you want job visibility, failure tracking, retries, Mission Control, and the rest of the Rails operational stack, Solid Queue's fiber mode gets you that concurrency with a speed tradeoff that's worth it -- you still get unbounded fibers per process while keeping database connections flat. With this patch, you just set `fibers: N` and keep building.

---

The PR is [up on GitHub][pr]. The [benchmark suite][bench] is open source, if you want to run your own numbers or challenge mine.

[async-article]: /async-ruby-is-the-future/
[pr]: https://github.com/rails/solid_queue/pull/728
[RubyLLM]: https://rubyllm.com
[Chat with Work]: https://chatwithwork.com
[async-job]: https://github.com/socketry/async-job
[async]: https://github.com/socketry/async
[async-http]: https://github.com/socketry/async-http
[Mission Control]: https://github.com/rails/mission_control-jobs
[Samuel Williams]: https://github.com/ioquatix
[bench]: https://github.com/crmne/solid_queue_bench
