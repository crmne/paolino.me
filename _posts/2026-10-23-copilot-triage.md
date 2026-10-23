---
layout: post
title: "I Get 215 GitHub Notifications a Day, So I Built a Bot to Triage Them"
seo_title: "Copilot Triage: AI Issue and Pull Request Triage for GitHub"
description: "My repositories send me about 215 GitHub notifications a day. Copilot Triage reads them, answers reporters when it can help, and sorts everything that needs me into one board."
date: 2026-10-23
tags: [Ruby, RubyLLM, AI, Agents, GitHub, Open Source, Copilot Triage]
image: /images/copilot-triage.png
video: https://talks.paolino.me/blog/copilot-triage.mp4
sendfox_campaign_id: 3082110
---
When your open source project gets popular, the real work starts.

I counted everything that happened in my repositories in the last 30 days, leaving out what I did myself:

- **42 new issues and pull requests a day** from people. [Spotifast](https://github.com/crmne/spotifast) and [ZapFast](https://github.com/crmne/zapfast), both two months old, brought in about 430 each. [RubyLLM](https://github.com/crmne/ruby_llm) brought in about 270.
- **49 comments and review comments a day** from people.
- **About 125 comments a day from review bots.** [CodeRabbit](https://www.coderabbit.ai) alone left 2,669 review comments, and [Copilot code review](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/request-a-code-review/use-code-review) another 974.

That's about 215 notifications a day, every day, on top of building the things people are filing issues about. Each one is an email, a badge on the bell, a push on my phone. I can't read all of them, and the important ones get buried under the rest: a pull request waiting for my sign-off ends up under fifty comments about a bug that was fixed last week.

So I built [Copilot Triage](https://github.com/crmne/copilot-triage). It reads every issue, discussion, and pull request, answers the reporter when it has something useful to say, and puts everything on a board sorted by what it needs from me. I turned off GitHub's email and open the board, a [GitHub Project](https://docs.github.com/en/issues/planning-and-tracking-with-projects), instead.

It's an independent open source project, not made by GitHub. The name comes from what it runs on: your [GitHub Copilot](https://github.com/features/copilot) allowance by default, or any model through [RubyLLM](https://rubyllm.com).

## The board

<img src="/images/copilot-triage-board.png" alt="The Maintainer board for RubyLLM: Sign off, Decide, Do, Their move and Not now columns, each card with a priority and a next step." width="1680" height="835" loading="lazy" decoding="async">

Every issue and pull request lands on the board, in the column for what it needs from me:

- **Sign off**: pull requests that were reviewed and are ready for me to merge.
- **Decide**: questions only I can answer, such as whether a feature fits.
- **Do**: work that's mine, like a confirmed bug or a pull request nobody has reviewed yet.
- **Their move**: waiting on the reporter or the contributor.

Each card has a priority and a one-line next step, so I know what to do before I open it. Urgent issues get assigned to me, and my review is requested on the pull requests that need it.

## What it does with each report

When someone opens an issue, the agent investigates with six read-only tools:

- `search_repository` finds literal matches in the docs and source paths you configure.
- `search_issues` looks for earlier issues about the same problem.
- `list_releases` lists recent releases with their notes.
- `search_changes` searches release notes and unreleased commits for a phrase, to tell whether a fix already shipped or is still on the main branch.
- `read_evidence` opens a file, issue, release, or pull request diff that one of the searches turned up.
- `submit_decision` hands over its decision: labels, an optional reply, and the next step for the card on the board.

It picks which tools to use and in what order, and then decides what would help. Usually that's a label and nothing else. When it can help, it posts one reply: the answer from the docs, the release that fixed it, the existing issue it duplicates, the one question the report is missing, or a short summary of a long report.

Discussions get answered from the docs, and a discussion that's really a bug report moves to an issue. For pull requests, it requests a [Copilot code review](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/request-a-code-review/use-code-review) when a change deserves one, reads the verdict when it arrives, and checks the contribution guidelines, like opening an issue first or attaching screenshots for UI changes. Merging is always up to me.

## It used to reply too much

Before this release I went through everything triage did across my repositories in one week. Labels were right 95% of the time. Replies were much worse: only a third of them actually helped anyone. The rest were things like "Thanks for the report!", a second and third diagnostic question after the reporter had already answered the first, or a link to an issue that was already linked in the thread.

Each of those replies is another notification, for the reporter and for me. A triage bot that adds noise defeats the point.

So it now replies much less. A thank-you gets no answer. When a reporter answers its question, it doesn't ask another one unless the answer reveals something new. After I comment, it replies at most twice more, then stops and moves the card to Decide. A clear report gets labels and no comment.

## One agent instead of 2,035 lines of YAML

My first attempt used [GitHub Agentic Workflows](https://github.com/github/gh-aw). For RubyLLM, the [compiled workflow](https://github.com/crmne/ruby_llm/blob/d04b4eeb341d76440bee9a029f150b7598e5cfcc/.github/workflows/issue-assessment.lock.yml) was 2,035 lines of YAML: tool gateways, agent jobs, a threat detector, safe-output jobs, and failure reporting. Then it started [opening issues about its own failures](https://github.com/crmne/ruby_llm/issues/922) and [commenting about its detector failing](https://github.com/crmne/ruby_llm/issues/913), which was more email, not less.

Copilot Triage is a [RubyLLM](https://rubyllm.com) agent with a system prompt and the six tools above:

```ruby
class TriageAgent < RubyLLM::Agent
  instructions { system_prompt }
  tools do
    [SearchRepository, SearchIssues, ListReleases, SearchChanges, ReadEvidence, SubmitDecision]
      .map { |tool| tool.new(toolbox) }
  end
end
```

The agent picks what to search and reads what it finds, with a budget of 12 searches and reads per report. Its last call submits a decision. The model can't change anything on GitHub: there's no shell, no file access, and no tool that writes. Ruby checks the decision, re-reads the report, verifies the evidence the model cited, and only then labels, comments, closes, or moves the card. If the report changed while the agent was working, it's left alone.

When something goes wrong, the error goes to the [GitHub Actions](https://github.com/features/actions) job summary. It doesn't open an issue about it.

It still makes mistakes. A wrong label costs me a click to fix, but a wrong reply costs the reporter's time and some goodwill toward the project, which is why the latest release went into making it reply less.

## Picking the model

I didn't want to guess which model to recommend, so there's a [`RubyLLM::Evaluation`](https://rubyllm.com) built from real and synthetic reports. Each case says what should happen: a reply with specific content, or no reply at all for a thank-you, a stop request, or a question that was already answered. A case passes only with the right outcome within its call budget.

The last full comparison ran each case twice:

| Model | Passed | Unneeded replies | Missed help | Cost per assessment |
| --- | --- | --- | --- | --- |
| GPT-5.6 Luna (default) | 29/30 | 0 | 1 | $0.0039 |
| GPT-6 Luna | 23/30 | 3 | 2 | $0.0023 |
| Claude Haiku 4.5 | 19/30 | 1 | 10 | $0.0228 |
| GPT-5 mini | 8/30 | 9 | 0 | $0.0087 |

GPT-5 mini replies to almost everything. Claude Haiku stays quiet even when the docs have the answer. GPT-6 Luna is cheaper but misses more and replies more when it shouldn't. You can run the same evaluation against any model:

```sh
EVAL_LIVE=true TRIAGE_MODEL=gpt-5.6-luna bundle exec rake ruby_llm:eval
```

## Cost

By default it runs on your Copilot allowance, at about a cent or less per report at [GitHub's listed prices](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing). When the allowance runs out, it can switch to an API key and keep going.

You can also skip Copilot and set `engine: rubyllm` to run the same agent on any provider RubyLLM supports: your company's [OpenAI](https://platform.openai.com) or [Anthropic](https://www.anthropic.com/api) key, [OpenRouter](https://openrouter.ai), [Amazon Bedrock](https://aws.amazon.com/bedrock/), [Azure](https://azure.microsoft.com/en-us/products/ai-foundry), or a local model on [Ollama](https://ollama.com).

## Try it

It's a [GitHub Action](https://github.com/marketplace/actions/copilot-triage). You need a token, a `triage.yml` file with your labels and project rules, and a short workflow file. It runs on all my repositories, from [RubyLLM](https://github.com/crmne/ruby_llm) to [Spotifast](https://github.com/crmne/spotifast).

[Copilot Triage on GitHub](https://github.com/crmne/copilot-triage)
