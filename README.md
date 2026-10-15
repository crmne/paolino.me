# My homepage

[Go to it](https://paolino.me)

## Scheduled publishing

The Pages workflow builds on pushes to `main` and at minute 17 of every hour
(UTC). Jekyll excludes future-dated posts until their front-matter date and time
have passed. Use an explicit UTC offset when a post needs a specific publication
time. The next successful build publishes it.

Hourly builds give publishing another chance when GitHub delays or drops a
scheduled run, and avoid the busy start of the hour. GitHub Actions schedules
are best-effort, so publication at an exact time is not guaranteed. To publish
an eligible post immediately, run:

```bash
gh workflow run jekyll.yml --repo crmne/paolino.me --ref main
```

## SendFox campaigns

This site includes a post-build integration that syncs published posts to SendFox draft campaigns.

- One post maps to one campaign via a stable post key derived from the post URL.
- Existing draft campaigns are updated on every build.
- Sent campaigns are never modified.
- The plugin never auto-sends campaigns.

### Mermaid diagrams

The SendFox workflow installs Mermaid CLI from `tools/mermaid/package-lock.json`
with `npm ci`, and caches npm downloads using the lockfile. The manifest pins
the CLI version, and the lockfile pins its transitive dependencies. Renovate's
npm manager discovers this manifest automatically.

The renderer stays on CLI 11 because the SendFox plugin uses `-w` and `-H`,
which CLI 12 removed. CI checks these options before syncing drafts.

To install the same renderer locally:

```bash
npm ci --prefix tools/mermaid
export PATH="$PWD/tools/mermaid/node_modules/.bin:$PATH"
mmdc --version
```

Use the Node.js version pinned in `.github/workflows/jekyll.yml`. Puppeteer
downloads its matching headless browser during installation. Existing diagram
PNGs in `images/sendfox-mermaid/` are reused; new diagrams require the renderer.
The tooling directory is excluded from the published site.

### Environment variables

- `SENDFOX_API_TOKEN`
- `SENDFOX_FROM_NAME`
- `SENDFOX_FROM_EMAIL`
- `SENDFOX_DRY_RUN=1` (optional)

### Optional post-level campaign pinning

If you want to pin a post to a specific SendFox campaign ID, set it in front matter:

```yaml
sendfox_campaign_id: 12345
```

or:

```yaml
sendfox:
  campaign_id: 12345
```

For new posts, SendFox generates the campaign ID on first creation. You cannot choose it during `POST /campaigns`.

Use this backfill helper after campaigns are created:

```bash
SENDFOX_API_TOKEN=... bundle exec ruby scripts/sendfox_backfill_ids.rb
```

Write IDs into front matter:

```bash
SENDFOX_API_TOKEN=... bundle exec ruby scripts/sendfox_backfill_ids.rb --apply --verbose
```

### CLI for safe testing

Preview the payload and rendered email HTML without touching SendFox:

```bash
bundle exec ruby scripts/sendfox_campaigns_cli.rb preview \
  --html-out /tmp/sendfox-preview.html \
  --json-out /tmp/sendfox-preview.json
```

Run the publish flow manually in dry-run mode:

```bash
bundle exec ruby scripts/sendfox_campaigns_cli.rb publish --dry-run
```

Force update-existing-draft behavior from CLI:

```bash
bundle exec ruby scripts/sendfox_campaigns_cli.rb publish --update-existing-draft
```
