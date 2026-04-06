---
layout: post
title: "Your Agent's Context Window Is Not a Junk Drawer"
date: 2026-04-07
description: "Most of what's in your agent's context window shouldn't be there."
tags: [AI, LLM, MCP, Agents, Developer Experience]
image: /images/context-rot.png
---

Your agent's context window is the most precious resource it has. The more you stuff into it, the worse your agent performs.

Researchers call it [context rot](https://research.trychroma.com/context-rot): the more tokens in the window, the harder it becomes for the model to follow instructions, retrieve information, and stay on task. The model essentially becomes _stupid_.

This holds true regardless of how big the window is, yet most agent setups treat the context window like a junk drawer.

"Just toss it in there, the LLM will figure it out!"

## MCP: the biggest offender

Don't get me wrong. MCP is a fine idea. You need to talk to a service? Grab an MCP server, plug it in, and you're running in ten minutes. For prototyping, for exploration, for answering "is this even worth building?", it's great.

The problem is what happens next. Which is: nothing.

People leave the MCP servers plugged in. They add more. Every MCP server you connect dumps tool descriptions, schemas, and instructions into your context. You didn't write those. You didn't optimize them. You probably haven't even read them. You're handing over a chunk of your context window to whatever some third party decided to shove in there.

You're not just introducing performance problems. You're introducing security problems. Those tool descriptions are text that gets interpreted by an LLM. You're injecting untrusted content directly into the brain of your agent. Every MCP server is a prompt injection surface you didn't audit.

Say you need a tool that checks the weather. You could plug in an MCP server and get dozens of tool descriptions, parameter schemas, and whatever instructions its author decided to write. Or you could write this:

```ruby
class Weather < RubyLLM::Tool
  description "Gets current weather for a location"

  param :latitude, desc: "Latitude (e.g., 52.5200)"
  param :longitude, desc: "Longitude (e.g., 13.4050)"

  def execute(latitude:, longitude:)
    url = "https://api.open-meteo.com/v1/forecast?latitude=#{latitude}&longitude=#{longitude}&current=temperature_2m,wind_speed_10m"
    Faraday.get(url).body
  rescue => e
    { error: e.message }
  end
end
```

Twelve lines of [RubyLLM](https://rubyllm.com). You wrote the description, so you know exactly what tokens are going into your context. You wrote the parameters, so the model gets precisely the interface it needs, no more. You own it, you can tune it, and nobody can inject anything into your agent's brain through it.

Use MCP to prototype. Then replace it with crafted tools you actually control.

## Batteries, old cables, and takeout menus

MCP gets the most attention, but it's not the only way people fill the drawer.

Look at what comes back from your tools. Your RAG retrieves ten full documents when the model needs a paragraph. Your tool returns a massive JSON blob when the model needs two fields. Your API response is stuffed with nested objects nobody asked for. You're paying for every one of those tokens with your agent's IQ.

The fix is simple: give the model just enough to make a decision, then let it dig deeper. At [Chat with Work](https://chatwithwork.com), when the agent searches your Google Drive, we don't dump entire files into context. The search tool returns only some metadata and a single line from the file, the line that matched the search keywords. Fifty results, fifty lines. The AI reads those, decides which files actually matter, and only then reads them. If a file is too large, it reads it in chunks. At every step, the model is only looking at what it needs. It stays sharp because we don't let it get buried.

Then there's the stuff you wrote yourself. Your system prompt is context. Your tool descriptions are context. Your parameter schemas are context. Every edge case, every guardrail, every overly detailed description competes for attention. You think you're being thorough. You're actually drowning the instructions that matter in a sea of instructions that don't. A focused system prompt will outperform an exhaustive one every time.

Same problem with tool count. You hand-crafted 40 beautiful tools. Your agent needs 5 for this task. The other 35? Dead weight. They sit in context doing nothing except making the model slower at picking the right one. Scope your tools to the task, not to everything the agent might ever need.

And the conversation itself keeps growing. Every message, every tool call, every result, every error stays in the window. Dozens of turns in, the topic has shifted three times, and most of your context is stale. You're dragging around the whole history of a conversation that's moved on. Prune what you don't need. Compact when you can. Teach your users to start fresh.

## Every token should earn its place

The context window is not a junk drawer. It's a workbench. Everything on it should be there for a reason, and you should be able to say what that reason is.

So before you plug in another MCP server, add another RAG source, or write another paragraph in your system prompt, ask yourself one question: is this worth making my agent dumber?

Because that's the trade you're making. Every time.
