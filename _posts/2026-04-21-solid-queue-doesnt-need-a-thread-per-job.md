---
layout: post
title: "Making the Rails Default Job Queue Fiber-Based"
date: 2026-04-21
description: "I tried Async::Job for my LLM apps, hit its limits, and patched Solid Queue to run jobs as fibers instead."
tags: [Ruby, Async, Rails, Solid Queue, Performance, Concurrency, Open Source]
image: /images/solid-queue-async.webp
sendfox_campaign_id: 2790538
---
Last year I moved the LLM streaming jobs in [Chat with Work][] to [Async::Job][async-job]. It was fast. Genuinely fast. Fiber-based execution with Redis, thousands of concurrent jobs on a single thread. I was so convinced that I [wrote a whole post][async-article] about why async Ruby is the future for AI apps and recommended it to everyone.

Then I started hitting walls.

Async::Job doesn't persist jobs. They go into Redis and they're gone. [Mission Control][] shows nothing. Background jobs in Rails are already quieter than the rest of your application -- they fail without anyone noticing unless you go looking. Even with Honeybadger catching exceptions, I still want to see the full picture: which jobs are queued, which are running, which failed, what the system looks like right now. Without job persistence, you don't get that.

Solid Queue is the default in Rails 8. Every new Rails app ships with it. When someone picks up Rails to build an LLM application and their 25-thread worker pool can only handle 25 concurrent streaming conversations, the answer shouldn't be "swap your entire job backend." It should be "change one line of config."

So I [opened a PR][pr].

## Threads vs fibers, quickly

If you already know this, [skip ahead to the config](#the-switch).

Solid Queue runs each job on its own thread. Threads can all query the database concurrently, so each one needs its own connection, plus its own stack memory and a slot in the OS scheduler. For a job that crunches data for 30 seconds, that's fine -- the thread is busy. For a job that streams an LLM response for 30 seconds but spends 99% of that time waiting for tokens, the thread is just sitting there holding resources.

Fibers sidestep all of this. Cooperatively scheduled, running in userspace on a single thread. When a fiber hits I/O -- a network call, a database query, waiting for the next token -- it steps aside and another fiber picks up. One thread, hundreds of concurrent jobs. No OS scheduling overhead, and for ordinary Active Record usage on Rails 7.2+, a much smaller database pool. The [async][] gem handles this for you: your code yields at I/O boundaries without you changing anything.

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

`threads` or `fibers`. Pick one per worker. One more thing in your Rails app:

```ruby
# config/application.rb
config.active_support.isolation_level = :fiber  # required for fibers
```

Fibers share a thread, so they need fiber-scoped state instead of the default thread-scoped state. The patch checks this at boot and tells you if it's wrong.

## Under the hood

The core of the patch is `FiberPool`. One thread, one [async][] reactor, a semaphore capping concurrency at whatever number you set:

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

When the worker picks up jobs, it hands them to the pool. Each one becomes a fiber:

```ruby
def schedule_pending_executions(semaphore)
  while execution = next_pending_execution
    semaphore.async(execution) do |_execution_task, scheduled_execution|
      perform_execution(scheduled_execution)
    end
  end
end
```

Each job runs as a fiber. When it hits I/O, it yields. The reactor picks up another fiber. One thread, hundreds of jobs, switching at I/O boundaries instead of waiting for the OS to preempt.

CPU-bound work gets nothing from fibers. They don't parallelize computation. But most of what job queues do is wait on I/O, and that's exactly where fibers win. If a CPU-bound fiber blocks the reactor, Solid Queue's supervisor still runs fine on its own process.

## The database connection math

I [wrote about this last year][async-article]:

> For 1000 concurrent conversations using traditional job queues like SolidQueue or Sidekiq, you'd need 1000 worker threads. Each worker thread holds its database connection for the entire job duration. That's 1000 database connections for threads that are 99% idle, waiting for streaming tokens.

That was the theory. Here's the actual math from the patch.

A Solid Queue worker needs database connections for three things: polling for jobs, heartbeats, and running jobs. With threads, every thread can query the database at the same time, so each one holds its own connection. That's `threads + 2`: one per thread, plus two for the worker itself.

With fibers on Rails 7.2+, all fibers run on one reactor thread. The pool savings come from ordinary Active Record query paths releasing connections between DB operations instead of holding them for the fiber's lifetime. In practice, that means the minimum is often `1 + 2 = 3`: one execution connection, plus two for the worker itself. If your jobs are DB-heavy, use long transactions, or pin connections with APIs like `ActiveRecord::Base.connection`, increase the pool and fibers will check out separate connections concurrently.

Same concurrency, wildly different connection costs:

| Concurrent jobs | Thread DB pool minimum (per process) | Fiber DB pool minimum (per process) |
|---|---|---|
| 10 | 12 | 3 |
| 25 | 27 | 3 |
| 50 | 52 | 3 |
| 100 | 102 | 3 |
| 200 | 202 | 3 |

Thread scales linearly. Fiber stays flat. Multiply by the number of worker processes and the gap gets dramatic: 6 processes with 50 concurrent jobs means 312 connections for thread mode, 18 for fiber. PostgreSQL's default `max_connections` is 100.

The patch detects your Rails version and calculates the right pool size automatically.

The benchmarks below use two pool policies. The primary Solid Queue comparison deliberately gives both modes the same pool, `DB_POOL = concurrency + 5` per worker process, so it measures the executor instead of measuring pool starvation. The stress suite uses mode-specific pools to show the operational failure envelope under higher connection demand.

## The benchmarks

I reran the benchmark suite on April 28, 2026. The headline Solid Queue comparison covers four workloads across per-process concurrency 5, 10, 25, 50, and 100; process counts 1, 2, and 6; and both execution modes. Three runs per cell, median real run reported, with total concurrency capped at 60 so the main comparison stays about executor behavior.

The workloads:

- **Sleep**: 50ms `Kernel.sleep`. Pure cooperative wait. The I/O upper bound.
- **Async HTTP**: HTTP request to a local server with 50ms delay via [Async::HTTP][async-http]. Real fiber-friendly I/O.
- **CPU**: 50,000 SHA256 iterations. Pure computation. The control.
- **RubyLLM Stream**: Actual [RubyLLM][] chat completion through a fake OpenAI SSE endpoint, with token-by-token Turbo Stream broadcasts. 40 tokens at 20ms each. The closest thing to a production AI workload you can benchmark repeatably.

### Results

| Workload | Best throughput | Avg paired delta | Best paired delta |
|---|---|---|---|
| RubyLLM Stream | fiber, 7.01 j/s | **+11.9%** | **+21.8%** |
| Async HTTP | fiber, 492.82 j/s | **+9.5%** | **+25.5%** |
| Sleep | fiber, 500.50 j/s | **+7.4%** | **+15.9%** |
| CPU | fiber, 110.02 j/s | +0.6% | +2.4% |

RubyLLM Stream is the workload that matters. It runs an actual [RubyLLM][] chat completion with streaming, database writes, and Turbo broadcasts per token -- the same thing [Chat with Work][] does in production. Fiber wins every single paired experiment there: 9 out of 9.

The CPU row is the control. Fibers don't help computation, and the average confirms it: essentially flat. That's how you know the I/O gains are real and not measurement noise.

That table shows the best observed point and the paired-cell deltas. Here's the full spread. Some configurations favor threads for synthetic workloads, but the paired averages are the steadier signal: fiber wins the I/O workloads, and RubyLLM Stream always favors fiber.

![Solid Queue fiber over thread throughput ranges across all workloads.](/images/solid-queue-headline-fiber-vs-thread.svg)

The newer suite also adds database-shaped workloads. With matched pools, short DB bursts still favor fiber: `db_queries` averages +12.6%, and a read/API/write mix averages +6.9%. The transaction case is the useful caveat: when each job pins a connection for the whole transaction, fiber still averages +3.5%, but the win is less consistent. That's exactly the workload where you should be more careful with pool sizing.

## Thread mode hit the wall

Those benchmarks cap total concurrency at 60. I wanted to see what breaks when you push past that, so I ran a stress suite: per-process concurrency 25, 50, 100, 150, and 200; process counts 2 and 6; three runs per cell. Read this as a current Solid Queue failure-envelope test, not a universal law about threads and fibers.

The result is stark. Thread mode only completed the smallest cell for each workload. Fiber mode completed every planned cell.

| Workload | Thread cells completed | Fiber cells completed |
|---|---|---|
| Sleep | 1/10 | 10/10 |
| Async HTTP | 1/10 | 10/10 |
| RubyLLM Stream | 1/10 | 10/10 |

![Solid Queue stress cell status.](/images/solid-queue-stress-cell-status.svg)

PostgreSQL's default `max_connections` is 100. In this stress run, thread mode at concurrency 50 with 2 processes asked for 110 worker-pool connections. With 6 processes, even concurrency 25 asked for 180. The one surviving thread cell was the smallest: concurrency 25, 2 processes.

Fiber mode in the stress suite used a smaller mode-specific pool: 6 connections per process for 2-process runs, 10 per process for 6-process runs. That is 60 worker-pool connections at concurrency 200 across 6 processes, while thread mode would ask for 1,230. The exact constants are benchmark policy, but the shape is the point: thread mode's pool scales with job concurrency; fiber mode's pool scales with worker process overhead.

## One backend, two modes

Fiber mode isn't universally better. CPU-bound jobs get nothing from it. C extensions that aren't fiber-safe won't work. And that's fine -- you don't have to pick one.

As Trevor Turk pointed out in the PR discussion, that's the whole point: separately configured worker pools. Here's what [Chat with Work][] actually runs in production:

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

Async::Job is actually faster if you compare raw throughput against Redis. It is a backend comparison, not a Solid Queue executor comparison, but the ceiling is useful:

| Workload | Solid Queue fiber best | Async::Job best | Delta |
|---|---|---|---|
| RubyLLM Stream | 7.01 j/s | 16.94 j/s | +141.7% |
| Async HTTP | 492.82 j/s | 652.96 j/s | +32.5% |
| Sleep | 500.50 j/s | 644.98 j/s | +28.9% |
| CPU | 110.02 j/s | 125.75 j/s | +14.3% |

![Async::Job over Solid Queue fiber throughput ranges.](/images/solid-queue-headline-asyncjob-vs-fiber.svg)

If you want raw speed and don't need persistence, Async::Job is the right call. But if you want job visibility, failure tracking, retries, Mission Control, everything Rails gives you out of the box, fiber mode gets you there. Same concurrency. Flat database connections. You set `fibers: N` and keep building.

---

The PR is [up on GitHub][pr]. The [benchmark suite][bench] is open source. Run your own numbers, or challenge mine.

[async-article]: /async-ruby-is-the-future/
[pr]: https://github.com/rails/solid_queue/pull/728
[RubyLLM]: https://rubyllm.com
[Chat with Work]: https://chatwithwork.com
[async-job]: https://github.com/socketry/async-job
[async]: https://github.com/socketry/async
[async-http]: https://github.com/socketry/async-http
[Mission Control]: https://github.com/rails/mission_control-jobs
[bench]: https://github.com/crmne/solid_queue_bench
