# SendFox HTML Findings

This file captures practical findings from real `POST/PATCH/GET` tests against the SendFox campaigns API for this project.

## Scope

- Project file: `_plugins/sendfox_campaigns.rb`
- Endpoint used: `https://api.sendfox.com/campaigns`
- Validation source of truth: the HTML returned by `GET /campaigns/:id` after patching

## What SendFox Rewrites or Strips

Observed behavior from live campaigns:

- `h1`, `h2`, `h3`, `p`, and `div` inline styles are generally preserved in current SendFox output.
- table markup can be rewritten by the editor by appending empty rows (`<tr><td></td></tr>`), which creates visible spacing drift.
- `span` inline styles are preserved.
- absolute-position overlays are not reliable.
- hidden preheader tricks (`display:none` + invisible chars) can leak into visible content in SendFox output.
- `pre` can be flattened/reformatted in ways that harm code readability.

Implication: avoid using table wrappers for general layout spacing in SendFox campaigns.

## Current Rendering Strategy

### Layout and spacing

- Header title/date/author/read-link are rendered as styled `div` blocks.
- Body paragraphs/headings/lists/blockquote are rendered as native block tags with inline margins and typography.
- Media image + "Watch video/open post" are rendered as `div`/`p` blocks.
- Lists are rendered as native `ul/li` or `ol/li` blocks with explicit compact inline styles on both list and items.
- List item internals are normalized to inline-safe HTML by stripping `<p>` wrappers and collapsing duplicate `<br>` runs before rendering `<li>`.
- `ul/li` spacing uses inline `!important` on margin/padding to override SendFox/editor CSS that can otherwise reintroduce paragraph-like gaps.
- Paragraph conversion skips wrapping when the paragraph contains block-level HTML, preventing invalid nested markup during embedded-media expansion.

### Code blocks

- Code blocks are rendered as `div` cards (`label div` + `content div`).
- Trailing newline is removed to avoid extra blank line at block end.
- `sh/bash/shell/plaintext/text` are forced through plain rendering with `<br />` line flow.
- Shell-family labels are normalized to `BASH` (so `sh` does not appear as a separate label).
- For other highlighted languages (e.g. Ruby), Rouge HTML is kept with `<br />` to avoid span-balance breakage.
- For plain-rendered blocks, consecutive empty lines are collapsed.
- Code cards use tight monospace line-height to avoid "double-spaced" appearance after SendFox sanitization.

### Syntax highlighting

- Rouge spans are converted to inline `<span style="...">` colors.
- This works where Rouge emits token spans (e.g. Ruby, some shell tokens).
- `plaintext` is intentionally label-only (no syntax colors).
- `sh/bash/shell` are intentionally treated as plain (no syntax colors) to guarantee stable line rendering.
- Code text keeps normal single spaces and preserves indentation/multi-space runs only, avoiding "bloated" spacing in shell/plaintext blocks.

## Known Constraints

- Play icon overlay on image is not dependable in SendFox due style sanitization; avoid absolute positioning.
- "Preview text via hidden block" is not stable; avoid this method.
- For mandatory compliance, include unsubscribe link placeholder: `{{unsubscribe_url}}`.

## Test Workflow

Use this sequence when changing renderer behavior:

1. Local render check:

```bash
bundle exec ruby scripts/sendfox_campaigns_cli.rb preview \
  --html-out /tmp/sendfox-preview.html \
  --json-out /tmp/sendfox-preview.json
```

2. Publish to drafts (real API):

```bash
bundle exec ruby scripts/sendfox_campaigns_cli.rb publish
```

3. Verify sanitized result (critical):

```bash
# Fetch campaign and inspect returned HTML
GET /campaigns/:id
```

Do not trust only local HTML output. Always inspect the HTML returned by SendFox.

## If You Improve This Later

- Prefer native `div/p/h/ul/li` blocks for spacing-critical elements.
- Keep code rendering independent from `pre`.
- Prefer additive changes and verify against one real campaign before mass publish.
- Re-check the `cluster-headache-tracker` post: it historically exposed parser edge cases.
