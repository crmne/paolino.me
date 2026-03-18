# My homepage

[Go to it](https://paolino.me)

## SendFox campaigns

This site includes a post-build integration that syncs published posts to SendFox draft campaigns.

- One post maps to one campaign via a stable post key derived from the post URL.
- Existing draft campaigns are updated on every build.
- Sent campaigns are never modified.
- The plugin never auto-sends campaigns.
- Campaign email preheader text is sourced from post `description` (fallback: excerpt).

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
