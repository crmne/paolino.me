---
layout: post
title: Citations in RubyLLM 2.0
date: 2026-10-16
description: "RubyLLM 2.0 turns document, tool, and web citations from every provider into one Citation object you can render as footnotes."
tags: [Ruby, AI, LLM, Rails, Open Source, RubyLLM]
---

When a model tells your user "The contract can be terminated with 30 days' notice," the user needs to know where that comes from and which page to check. In RubyLLM 2.0 you ask for citations:

```ruby
chat = RubyLLM.chat(model: "claude-sonnet-5").with_citations
response = chat.ask "What are the termination conditions?", with: "contract.pdf"

response.citations.each do |citation|
  puts "p. #{citation.start_page}: #{citation.cited_text}"
end
```

The answer comes with the passage it's based on and the page it's on, so the user can read the source and check it.

`with_citations` turns on document citations for Anthropic, Cohere, and Claude on Bedrock. `with_citations(false)` turns them off.

## Every Format, One Object

Every provider has its own citation format. Anthropic returns citation blocks. Gemini returns grounding metadata with byte offsets. OpenAI hangs annotations off the response text. Perplexity sends a list of URLs on every chunk. If you build footnotes against each one directly, you write the footnote feature once per provider.

RubyLLM turns all of them into `RubyLLM::Citation`:

| Reader | What it tells you |
|---|---|
| `url`, `title` | The source |
| `cited_text` | The quoted passage from the source |
| `text` | The part of the answer this citation supports |
| `start_index`, `end_index` | Where that part sits in `response.content` |
| `source_id` | The provider's ID for the source, like a file ID |
| `source_index` | The source's zero-based position |
| `start_page`, `end_page` | The PDF page range, from 1, inclusive |

Whatever the provider didn't report is `nil`. A web citation often has a URL and nothing else.

When you do get positions, they're character offsets into the answer, ready to slice:

```ruby
response.citations.each do |citation|
  next unless citation.end_index

  puts response.content[citation.start_index...citation.end_index]
end
```

Gemini reports byte offsets, which would drift the moment your answer contains an accented letter. RubyLLM converts them to characters, so your footnote lands after "Café" and not in the middle of it.

## Your Tools Can Be Cited Too

Citations matter most in RAG, and that's also where they usually get lost: your tool returns a JSON blob, and the model paraphrases it with no trail back. Return `RubyLLM::SearchResults` instead:

```ruby
class KnowledgeBase < RubyLLM::Tool
  description "Searches the company knowledge base"
  parameter :query, description: "What to look for"

  def execute(query:)
    docs = Document.search(query)
    return "No matching documentation found." if docs.empty?

    RubyLLM::SearchResults.new(
      *docs.map { |doc| { title: doc.title, url: doc.url, text: doc.body } }
    )
  end
end

response = RubyLLM.chat(model: "claude-sonnet-5")
  .with_tools(KnowledgeBase)
  .ask("How do I rotate an API key? Cite the docs.")

response.citations.first.url        # => the doc.url you returned
response.citations.first.cited_text # => the passage it relied on
```

Anthropic, Cohere, and Bedrock receive these as their native citable search results, including after a Rails chat is reloaded from the database. Other providers get the results as JSON text, which they can read but not formally cite.

## Web Search Brings Its Own

Search citations need no setting. Turn on the provider's search tool and they show up:

```ruby
response = RubyLLM.chat(model: "claude-sonnet-5")
  .with_provider_tools(:web_search)
  .ask("What is the latest stable Ruby version?")

response.citations.map(&:url).compact.uniq
```

The same line works with OpenAI, Gemini, xAI, and the other providers whose search tool RubyLLM knows. Perplexity's Sonar models search on every request, so they need no setup.

## Streaming and Rails

Citations arrive on streaming chunks as they come, and the final message collects them all, deduplicated. Some providers only send citations at the end, so build the finished footnotes from the final message.

With `acts_as_chat` and `acts_as_message`, citations are saved as JSON and come back as `Citation` objects:

```ruby
chat = Chat.create!(model: "claude-sonnet-5").with_citations
chat.ask "What are the termination conditions?", with: "contract.pdf"

chat.reload.messages.last.citations # => [#<RubyLLM::Citation ...>, ...]
```

The 2.0 install and upgrade generators add the column. One limit to know: Anthropic won't combine document citations with `with_schema`, so a single request gets either citations or structured output.

The [citations guide](https://rubyllm.com/citations/) has a footnote renderer you can copy. Models still make mistakes, and citations give your users a way to check the answer against its source.
