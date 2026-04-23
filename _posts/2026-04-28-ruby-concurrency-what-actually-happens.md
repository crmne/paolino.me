---
layout: post
title: "Ruby Concurrency: What Actually Happens"
date: 2026-04-28
description: "Every 'what happens when' question about Ruby concurrency, answered with diagrams."
tags: [Ruby, Concurrency, Async, Fibers, Performance]
image: /images/ruby-concurrency.png
---
Since I wrote about [async Ruby][async-article] and [patched Solid Queue to support fibers][sq-article], people keep asking the same questions. What happens when a fiber blocks? Don't you still need threads? What about database transactions? What about Ractors?

This post answers all of it. From the ground up.

## The four primitives

Ruby gives you four concurrency primitives: processes, threads, fibers, and Ractors. They nest. Every process has an implicit "main Ractor" where your code runs by default, so you never have to think about Ractors unless you explicitly create one. Without Ractors, the hierarchy is simply process -- threads -- fibers. With Ractors, it becomes:

<div class="mermaid">
graph TD
    P[Process] --> R1["Ractor 1 (GVL 1)"]
    P --> R2["Ractor 2 (GVL 2)"]
    R1 --> T1[Thread 1]
    R1 --> T2[Thread 2]
    R2 --> T3[Thread 3]
    T1 --> F1[Fiber A]
    T1 --> F2[Fiber B]
    T2 --> F3[Fiber C]
    T3 --> F4[Fiber D]
    T3 --> F5[Fiber E]
    style P fill:#4a90a4,color:#fff
    style R1 fill:#c084fc,color:#fff
    style R2 fill:#c084fc,color:#fff
    style T1 fill:#7fb069,color:#fff
    style T2 fill:#7fb069,color:#fff
    style T3 fill:#7fb069,color:#fff
    style F1 fill:#e8a87c,color:#fff
    style F2 fill:#e8a87c,color:#fff
    style F3 fill:#e8a87c,color:#fff
    style F4 fill:#e8a87c,color:#fff
    style F5 fill:#e8a87c,color:#fff
</div>

Think of your computer as an office building.

**Processes** are fully isolated: separate offices, each with its own locked door, furniture, and files. Each process has its own memory, its own Ruby VM, and its own GVL. When you run Puma with 3 workers, you get 3 processes. They can't corrupt each other's state because they don't share memory. The OS schedules them independently. The cost: each one loads your entire application into memory.

**Ractors** sit between processes and threads: offices that share a mailroom but not their filing cabinets. Each Ractor has its own GVL, so threads in different Ractors can execute Ruby code truly in parallel, but they can only pass notes to each other -- no shared mutable objects. You communicate via message passing, copying or moving data between them. Every Ruby process has a "main Ractor" where all your code runs by default. Creating additional Ractors is opt-in.

**Threads** live inside a process and share its memory: workers sharing the same office, accessing the same filing cabinets, coordinating to avoid collisions. The OS preemptively schedules them, meaning it can pause any thread at any time and switch to another. You don't control when this happens. The GVL prevents threads from executing Ruby code in parallel, but it releases the lock during I/O. So two threads can wait on two different network calls simultaneously, but they can't crunch numbers at the same time.

**Fibers** live inside a thread and are cooperatively scheduled: multiple tasks juggled by one worker at their desk. When they're waiting for something -- a phone call, a fax, a response -- they set it aside and pick up the next task. A fiber runs until it explicitly yields. When it hits I/O -- a network call, a database query, reading a file -- it yields to the reactor, and another fiber picks up. No OS involvement, no preemption. One thread can run thousands of fibers.

Here's what that means for cost:

| | Process | Ractor | Thread | Fiber |
|---|---|---|---|---|
| Memory | full app copy | ~thread + own GVL | ~8MB virtual | ~4KB initial, grows as needed |
| Creation time | ~ms | ~80μs | ~80μs | ~3μs |
| Context switch | kernel | kernel (threads within) | ~1.3μs (kernel) | ~0.1μs (userspace) |
| Isolation | Full (own memory) | Share-nothing (messages) | Shared memory | Shared thread |
| Parallelism | Yes | Yes (own GVL) | No (shared GVL) | No |
| I/O concurrency | Yes | Yes | Yes | Yes |
| Rails compatible | Yes | No | Yes | Yes |

Creation and switching benchmarks are from [Samuel Williams' fiber-vs-thread performance comparison][fiber-bench]. Fibers create 20x faster and switch 10x faster than threads. But the real cost difference is in what the OS sees: each thread is a kernel object with scheduler state, each fiber exists entirely in userspace. Ractors give you parallelism too, but can't run Rails. Everything is a tradeoff.

## How scheduling works

This is where most of the confusion lives. Let me show you what actually happens.

### Preemptive scheduling (threads)

The OS controls when threads switch. Your code has no say. A thread could be paused mid-calculation, mid-assignment, mid-anything.

<div class="mermaid">
sequenceDiagram
    participant OS as OS Scheduler
    participant T1 as Thread 1
    participant T2 as Thread 2
    participant LLM as LLM API

    T1->>LLM: Send request
    Note over T1: Waiting... (idle)
    OS->>OS: Time slice expired
    OS->>T2: Your turn
    T2->>LLM: Send request
    Note over T2: Waiting... (idle)
    OS->>OS: Time slice expired
    OS->>T1: Your turn
    Note over T1: Still waiting...
    OS->>OS: Time slice expired
    OS->>T2: Your turn
    Note over T2: Still waiting...
    LLM-->>T1: Response ready
    OS->>T1: Your turn (eventually)
    Note over T1: Finally processes response
</div>

The OS keeps switching between threads on a timer, even when they have nothing to do. Each switch costs a context save, a context restore, and a trip through the kernel. The thread that got the LLM response might not run immediately -- it has to wait for its next time slice.

For two threads doing I/O, this works fine. The overhead is noise. For 200 threads mostly sitting idle waiting for LLM tokens, the OS is spending most of its time switching between threads that have nothing to do.

### Cooperative scheduling (fibers)

Fibers switch only when they choose to. In practice, the [async][] gem makes this automatic: your code yields at I/O boundaries without you writing anything special.

<div class="mermaid">
sequenceDiagram
    participant R as Reactor
    participant F1 as Fiber 1
    participant F2 as Fiber 2
    participant LLM as LLM API

    R->>F1: Run
    F1->>LLM: Send request
    Note over F1: Yields (I/O wait)
    R->>F2: Run
    F2->>LLM: Send request
    Note over F2: Yields (I/O wait)
    Note over R: Both waiting, reactor sleeps
    LLM-->>F1: Response ready
    R->>F1: Resume immediately
    Note over F1: Processes response
    F1->>R: Done
    LLM-->>F2: Response ready
    R->>F2: Resume immediately
    Note over F2: Processes response
    F2->>R: Done
</div>

No OS involvement. No timer-based switching. When a fiber yields, the reactor checks which fibers have I/O ready and resumes them immediately. When nothing is ready, the reactor sleeps until something is. Zero wasted cycles.

## The GVL: why threads and fibers are more similar than you think

Here's the thing about threads in Ruby that most people miss.

The GVL means only one thread can execute Ruby code at a time. Threads run in parallel only during I/O, when the GVL is released. So if your workload is I/O-bound -- HTTP calls, database queries, LLM streaming -- threads give you I/O concurrency, not parallelism.

Fibers give you the same I/O concurrency. One fiber yields at I/O, another picks up. The difference: fibers do it without OS scheduling overhead, without the memory cost of a thread stack, and without needing a database connection per concurrent job.

If threads only help with I/O anyway, why pay their overhead?

There is one case where threads win: CPU-bound work that releases the GVL. Some C extensions (image processing, cryptographic operations) release the GVL while doing heavy computation. Multiple threads can then run those C extensions in parallel. Fibers can't do that. They share a thread.

For actual Ruby-level CPU parallelism, you need processes or [Ractors](#why-not-ractors). Processes are production-ready and Rails-compatible. Ractors are faster but still experimental.

## What happens when a fiber hits I/O

This is the happy path and the most common question.

```ruby
# Inside a fiber
response = Net::HTTP.get("api.openai.com", "/v1/completions")
```

Here's the full chain:

1. `Net::HTTP` opens a socket and sends the request
2. The socket isn't readable yet (the server hasn't responded)
3. Ruby calls `rb_io_wait` on the socket
4. The async gem's `Fiber.scheduler` intercepts this call
5. The scheduler suspends the current fiber and registers the socket with the event loop
6. The reactor runs other fibers while this one sleeps
7. When the socket becomes readable, the reactor resumes this fiber
8. `Net::HTTP` reads the response as if nothing happened

Your code doesn't change. No `await`, no callbacks, no promises. The same `Net::HTTP.get` call that works in a thread works in a fiber. The yield is invisible.

Bob Nystrom called this [the function color problem][function-color] in 2015. In languages with async/await, every function is either sync or async. An async function can only be called with `await`, and `await` can only live inside another async function. The color spreads upward through your entire call stack.

**Python:**

```python
# Python: the color spreads, and you need different libraries
async def get_user(id):
    async with aiohttp.ClientSession() as session:  # can't use requests
        response = await session.get(f"/users/{id}")  # must await
        return await response.json()                   # must await

async def handle_request():  # must be async because it calls get_user
    user = await get_user(1)  # must await
```

You can't use `requests` in async Python. You need `aiohttp`. You can't use `psycopg2`. You need `asyncpg`. The entire ecosystem splits in half: sync libraries and async libraries, doing the same thing differently.

**JavaScript:**

```javascript
// JavaScript: same problem, less severe (Node has fewer library splits)
async function getUser(id) {
  const response = await fetch(`/users/${id}`);  // must await
  return await response.json();                   // must await
}

async function handleRequest() {  // must be async
  const user = await getUser(1);  // must await
}
```

**Ruby:**

```ruby
# Ruby: no color
def get_user(id)
  response = Net::HTTP.get(URI("/users/#{id}"))  # just a normal call
  JSON.parse(response)                            # just a normal call
end

def handle_request
  user = get_user(1)  # just a normal call
end
```

Same `Net::HTTP`. Same `pg`. Same everything. The fiber scheduler intercepts I/O at the Ruby runtime level, below your code. Your methods don't know and don't care whether they're running in a thread or a fiber.

## What happens when a fiber does CPU-bound work

```ruby
# Inside a fiber
100_000.times { Digest::SHA256.hexdigest("work") }
```

This blocks the reactor. No other fiber runs until it finishes. There's no I/O boundary to yield at, so the fiber holds the thread.

<div class="mermaid">
sequenceDiagram
    participant R as Reactor
    participant F1 as Fiber 1 (CPU)
    participant F2 as Fiber 2 (I/O)

    R->>F1: Run
    Note over F1,F2: F1 doing CPU work...
    Note over F2: Waiting to run
    Note over F1,F2: F1 still computing...
    Note over F2: Still waiting
    F1->>R: Done
    R->>F2: Finally runs
</div>

This is not a bug. It's the tradeoff of cooperative scheduling. Fibers are designed for I/O-bound work. CPU-bound work should go on a thread, where the OS can preempt it.

With [Solid Queue's fiber mode][sq-article], this is a configuration choice:

```yaml
workers:
  - queues: [ chat, turbo, notifications ]
    fibers: 50       # I/O-bound: use fibers
  - queues: [ cpu ]
    threads: 2        # CPU-bound: use threads
```

One backend, two modes, matching the concurrency model to the workload.

## What happens when a fiber queries the database

The [pg gem][] has supported `Fiber.scheduler` since v1.3.0. When a fiber executes a query, the pg gem sends it non-blockingly via `PQsendQuery`, then calls `rb_io_wait` on the PostgreSQL socket. The scheduler intercepts this, suspends the fiber, and lets others run while PostgreSQL processes the query.

```ruby
# Inside a fiber
user = User.find(42)  # yields while waiting for PostgreSQL
```

The fiber yields. Other fibers run. When PostgreSQL responds, the reactor resumes the fiber. Your code doesn't know the difference.

### Connection sharing

With threads, every thread can query the database at the same time. Each one needs its own connection. With fibers, the important difference is that ordinary Active Record query paths can release connections between DB operations, so a much smaller pool is often enough. If you need more concurrent DB access, increase the pool and fibers will check out separate connections concurrently. The reactor never preempts a fiber -- it only switches when a fiber yields at an I/O boundary:

<div class="mermaid">
sequenceDiagram
    participant R as Reactor
    participant F1 as Fiber A
    participant F2 as Fiber B
    participant Pool as DB Pool (1 conn)
    participant PG as PostgreSQL
    participant HTTP as HTTP API

    R->>F1: Run
    F1->>Pool: Check out
    F1->>PG: SELECT * FROM users
    Note over F1: Yields (waiting for PG)
    R->>F2: Run
    F2->>HTTP: GET /api/data
    Note over F2: Yields (waiting for HTTP)
    PG-->>R: F1's result ready
    R->>F1: Resume
    F1->>Pool: Return
    F1->>R: Done
    HTTP-->>R: F2's result ready
    R->>F2: Resume
    F2->>Pool: Check out
    F2->>PG: UPDATE messages SET ...
    Note over F2: Yields (waiting for PG)
    PG-->>R: F2's result ready
    R->>F2: Resume
    F2->>Pool: Return
    F2->>R: Done
</div>

Active Record 7.2+ makes this work: ordinary query paths can release connections between DB operations instead of holding them for the fiber's lifetime. Check out, query, return. The minimum pool size is often 3 per process (1 execution + 2 for worker overhead), but jobs that hold transactions, use connection-local session state, or explicitly pin connections need more. For DB-heavy workloads, bump the pool size.

## What happens when a fiber starts a transaction

This is the question that worries people the most. If fibers share a connection, can one fiber's transaction leak into another?

No. Active Record handles this correctly.

When a fiber starts a transaction, it holds the connection for the entire duration -- from `BEGIN` to `COMMIT` or `ROLLBACK`. The connection is not released mid-transaction. Other fibers that need the database wait for the connection to be returned.

<div class="mermaid">
sequenceDiagram
    participant R as Reactor
    participant F1 as Fiber A
    participant F2 as Fiber B
    participant Pool as DB Pool (1 conn)
    participant PG as PostgreSQL

    R->>F1: Run
    F1->>Pool: Check out
    F1->>PG: BEGIN
    F1->>PG: UPDATE accounts SET ...
    Note over F1: Yields (waiting for PG)
    R->>F2: Run
    F2->>Pool: Check out
    Note over F2: Waits (connection held by F1)
    PG-->>F1: Result
    R->>F1: Resume
    F1->>PG: COMMIT
    F1->>Pool: Return
    F1->>R: Done
    Pool->>F2: Connection available
    F2->>PG: SELECT * FROM accounts
    Note over F2: Yields (waiting for PG)
    PG-->>F2: Result
    R->>F2: Resume
    F2->>Pool: Return
    F2->>R: Done
</div>

Under fiber isolation (`config.active_support.isolation_level = :fiber`), Active Record tracks connection ownership per fiber. The connection gets a real `Monitor` lock. No other fiber can touch it during a transaction.

Safe. No interleaving. Fiber B just waits.

For the target workload -- LLM streaming, HTTP calls -- database touches are short reads and status updates. Transactions are brief. The wait is negligible. If your jobs run long transactions, those jobs belong on a thread-based worker.

## What happens when you have too many fibers

Fibers aren't free. Each one uses memory (~4KB), and each one might hold open connections to external services. If you spawn 10,000 fibers that all hit the same API, you're opening 10,000 connections to that API. The API will not be happy.

This is [the point that f9ae8221b made on Reddit][reddit-thread]: async doesn't eliminate resource limits, it just changes where they show up. With threads, the limit is explicit: 25 threads, 25 concurrent jobs. With fibers, the limit is implicit: you keep going until something else breaks.

The fix is a semaphore. Solid Queue's `FiberPool` uses one:

```ruby
semaphore = Async::Semaphore.new(size)

# Only `size` fibers run concurrently
semaphore.async do
  perform_job
end
```

When you configure `fibers: 100` in Solid Queue, that's not "unlimited fibers." It's a semaphore capping concurrency at 100. You control the ceiling.

## "Why not just use more threads?"

Every time I write about fibers, someone asks this. If 25 threads isn't enough, why not 200? Or 1,000?

Three reasons.

**OS overhead scales badly.** [Samuel Williams' benchmarks][fiber-bench] show fibers allocate 20x faster (~3μs vs ~80μs), switch 10x faster (~0.1μs vs ~1.3μs), and achieve 15x higher throughput (~80,000 vs ~5,000 requests/second). The OS scheduler was designed for dozens of threads, not thousands.

**Each thread needs a database connection.** With Solid Queue, that's `threads + 2` connections per process. 200 threads across 2 processes means 404 connections. PostgreSQL's default max is 100.

**Threads are preempted even when idle.** An LLM streaming job spends 99% of its time waiting for tokens. The OS doesn't know that. It keeps switching to the thread, checking if it has work, switching away. Thousands of threads means thousands of pointless context switches.

Fibers don't have any of these problems. They yield voluntarily, share database connections, and use 250x less memory.

## "Why not Ractors?"

Ractors solve a different problem. Fibers give you I/O concurrency -- many things waiting at once. Ractors give you CPU parallelism -- many things computing at once.

Here's what they look like:

```ruby
# Two Ractors computing fibonacci in parallel
r1 = Ractor.new { fibonacci(38) }
r2 = Ractor.new { fibonacci(38) }

r1.value  # Ruby 4.0+
r2.value  # Both ran in parallel, each with their own GVL
```

Each Ractor has its own GVL, so they can execute Ruby code truly in parallel across CPU cores. The tradeoff: strict isolation. You can only share immutable (frozen) objects. Everything else gets copied or moved between Ractors via message passing. Access a mutable variable from an outer scope? `Ractor::IsolationError`.

When Ractors win, they win big. Fibonacci(38) five times: 0.68s with Ractors vs 2.26s sequential. 3.3x speedup. Real parallelism.

When they lose, they lose badly. JSON parsing 5 million documents: Ractors are **2.5x slower than sequential**. The Ruby VM's string interning table requires a global lock, and JSON parsing hammers it. The parallelism gain is wiped out by lock contention.

And the practical issues:

- **Still experimental in Ruby 4.0.** The goal is to remove the experimental flag in Ruby 4.1, but it's not there yet.
- **Most gems don't work.** Any gem using mutable constants, global variables, or class variables raises `Ractor::IsolationError`. That's most gems.
- **No Rails integration.** ActiveRecord, ActionCable, the router, the logger -- Rails is built on shared mutable state. None of it runs inside a Ractor.
- **No Ractor-based job queue exists.**
- **74 open issues** in the Ruby bug tracker as of early 2025, including segfaults and deadlocks.

For I/O concurrency, Ractors don't help at all. Each Ractor still has threads constrained by its own GVL. Fibers within those threads still do the actual I/O multiplexing. Ractors add CPU parallelism, which is not what LLM streaming needs.

If you need CPU parallelism in Ruby today, use processes. Puma already does this with workers. When Ractors graduate from experimental and the gem ecosystem catches up, they'll be a lighter-weight alternative to processes for CPU-bound work. That day hasn't come yet.

## "Isn't this just what JavaScript does?"

No. I showed the [code comparison above](#what-happens-when-a-fiber-hits-io). JavaScript's async/await is a colored concurrency model: the `async` keyword spreads upward through every caller. Ruby's fibers are colorless: your existing code works unchanged, and the scheduler handles yields below your code.

There's a deeper difference too. JavaScript runs on a single-threaded event loop. Ruby fibers run on top of a multi-threaded runtime. You can have multiple threads, each running its own reactor with its own fibers. You can mix fibers and threads in the same application. JavaScript can't do that.

## "Isn't this just what Go does?"

Closer. Goroutines are lightweight, cooperatively scheduled, and the runtime multiplexes them across OS threads. Conceptually similar to Ruby fibers.

Two differences:

1. **Go has true parallelism.** Goroutines run across multiple OS threads with no GVL equivalent. CPU-bound goroutines run in parallel. Ruby fibers don't.

2. **Ruby has existing code.** If you have a Rails application with hundreds of thousands of lines of Ruby, you can add fiber-based concurrency without rewriting anything. Your models, your controllers, your views, your gems -- they all work. With Go, you're rewriting.

If you're starting from scratch and need both I/O concurrency and CPU parallelism, Go is a strong choice. If you have a Ruby application and need I/O concurrency, fibers give you that without a rewrite.

## "Fibers need `Async do` blocks. That's still new syntax."

Someone on [Hacker News][hn-thread] called this out: I said "no async/await" but the examples show `Async do` and `.wait`.

Here's the actual change:

```ruby
# Before
chat = RubyLLM.chat
response = chat.ask("Hello")

# After
Async do
  chat = RubyLLM.chat
  response = chat.ask("Hello")
end
```

Two lines of wrapping. Your application code inside doesn't change. Your models don't change. Your gems don't change. Nothing gets a new keyword.

In Python, adopting async means rewriting every function signature in the call chain to `async def`, adding `await` to every call, and replacing your libraries. `requests` becomes `aiohttp`. `psycopg2` becomes `asyncpg`. Your test framework changes. Your middleware changes. It's a rewrite.

Two lines of wrapping vs. rewriting your stack. That's not even the same conversation.

## When to use what

<div class="mermaid">
flowchart TD
    A[What kind of work?] --> B{CPU-bound?}
    B -->|Yes| C{Need parallelism?}
    C -->|Yes| D{Rails?}
    D -->|Yes| E[Processes]
    D -->|No| H[Ractors]
    C -->|No| F[Threads]
    B -->|No| I[Fibers]

    style E fill:#4a90a4,color:#fff
    style H fill:#c084fc,color:#fff
    style F fill:#7fb069,color:#fff
    style I fill:#e8a87c,color:#fff
</div>

- **I/O-bound work** (LLM streaming, HTTP calls, webhooks, email delivery): **fibers.** Low overhead, high concurrency, shared database connections.
- **CPU-bound work** (image processing, data crunching, PDF generation): **threads.** The OS can preempt them, and C extensions can release the GVL for parallelism.
- **CPU parallelism with Rails**: **processes.** Each one gets its own GVL, its own memory, its own everything. Puma already does this.
- **CPU parallelism without Rails**: **Ractors** (when they graduate from experimental). Lighter than processes, true parallelism, but strict isolation means most gems don't work.
- **All of them at once**: that's what a well-configured Rails app does. Puma forks processes. Each process runs threads. Fibers run inside those threads for I/O-heavy jobs. They coexist.

```yaml
# Solid Queue: all three working together
workers:
  - queues: [ chat, turbo ]
    fibers: 50        # I/O-bound: fibers
    processes: 2       # parallelism: processes
  - queues: [ pdf, images ]
    threads: 4         # CPU-bound: threads
    processes: 1
```

No single model is universally better. The right answer is matching the model to the workload.

---

This covers every "what happens when" question I've gotten so far. If I missed yours, [open an issue][bench] or [find me on Twitter][@paolino].

[async-article]: /async-ruby-is-the-future/
[sq-article]: /solid-queue-doesnt-need-a-thread-per-job/
[async]: https://github.com/socketry/async
[pg gem]: https://github.com/ged/ruby-pg
[reddit-thread]: https://www.reddit.com/r/rails/comments/1lvhaf4/async_ruby_is_the_future_of_ai_apps_and_its/
[hn-thread]: https://news.ycombinator.com/item?id=44516555
[function-color]: https://journal.stuffwithstuff.com/2015/02/01/what-color-is-your-function/
[fiber-bench]: https://github.com/socketry/performance/tree/adfd780c6b4842b9534edfa15e383e5dfd4b4137/fiber-vs-thread
[bench]: https://github.com/crmne/solid_queue_bench
[@paolino]: https://twitter.com/paolino
