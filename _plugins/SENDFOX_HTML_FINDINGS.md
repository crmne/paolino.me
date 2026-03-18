# SendFox HTML Findings

This file captures practical findings from real `POST/PATCH/GET` tests against the SendFox campaigns API for this project.

## Scope

- Project file: `_plugins/sendfox_campaigns.rb`
- Endpoint used: `https://api.sendfox.com/campaigns`
- Validation source of truth: the HTML returned by `GET /campaigns/:id` after patching

## What SendFox Rewrites or Strips

Observed behavior from live campaigns:

- `h1`, `h2`, `h3`, `p` inline styles are often stripped or heavily rewritten.
- table markup and `td` inline styles are preserved much more reliably.
- `span` inline styles are preserved.
- absolute-position overlays are not reliable.
- hidden preheader tricks (`display:none` + invisible chars) can leak into visible content in SendFox output.
- `pre` can be flattened/reformatted in ways that harm code readability.
- trailing empty rows (`<tr><td></td></tr>`) may be injected by SendFox.

Implication: for deterministic spacing/layout, prefer table/td wrappers over heading/paragraph CSS.

## Current Rendering Strategy

### Layout and spacing

- Header title/date/author/read-link are rendered via table rows.
- Body paragraphs/headings/lists/blockquote are converted into spacing-controlled table wrappers.
- Media image + "Watch video/open post" link row are table-based for stable spacing.

### Code blocks

- Code blocks are rendered as table cards (`label row` + `code row`).
- Newlines are converted to `<br />`.
- Trailing newline is removed to avoid extra blank line at block end.
- Code cell line-height is intentionally tighter (`1.25`) to avoid "double-spaced" appearance after sanitization.

### Syntax highlighting

- Rouge spans are converted to inline `<span style="...">` colors.
- This works where Rouge emits token spans (e.g. Ruby, some shell tokens).
- `plaintext` has no lexer tokens by definition, so label-only styling is expected.
- Shell highlighting can be partial if Rouge returns few/no token classes for a snippet.

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

- Keep spacing-critical elements in table/td wrappers.
- Keep code rendering independent from `pre`.
- Prefer additive changes and verify against one real campaign before mass publish.
- Re-check the `cluster-headache-tracker` post: it historically exposed parser edge cases.
