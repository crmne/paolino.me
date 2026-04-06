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

Look at what comes back from your tools. RAG that retrieves ten full documents when the model needs a paragraph. A tool that returns a massive JSON blob when the model needs two fields. An API response stuffed with nested objects nobody asked for.

The fix is to give the model just enough to make a decision, then let it dig deeper. At [Chat with Work](https://chatwithwork.com), when the agent searches your Google Drive, we don't dump entire files into context. The search tool returns only some metadata and a single line from the file, the line that matched the search keywords. Fifty results, fifty lines. The AI reads those, decides which files actually matter, and only then reads them. If a file is too large, it even reads it in chunks. The model stays sharp because at every step it's only looking at what it needs.

Then there's the stuff you wrote yourself. Your system prompt is context. Your tool descriptions are context. Your parameter schemas are context. Every edge case in your system prompt, every overly detailed parameter description, every guardrail you can think of competes for the model's attention. A focused system prompt that covers the important things well will outperform an exhaustive one that covers everything poorly. Same goes for tool descriptions: say what the tool does and what the parameters mean, nothing more.

Even if every tool is hand-written and perfectly crafted, having 40 registered when your agent needs 5 for the current task means 35 tool definitions sitting in context doing nothing. Scope your agent's tools to the task at hand, not to everything it might ever need.

Lastly, the conversation itself. Every message, every tool call, tool result, error, schema definition stays in the window as your agent runs. Dozens of turns in, the conversation shifts topic and most of your context is now just chipping away at your agent's intelligence. Educate your users to start new chats. Prune what you don't need. Compact when you can.

## Every token should earn its place

The context window is not a junk drawer. It's a workbench. Everything on it should be there for a reason, and you should be able to articulate what that reason is.

Before you add another MCP server, another RAG source, another paragraph to your system prompt, ask yourself: is this worth making my agent dumber?
