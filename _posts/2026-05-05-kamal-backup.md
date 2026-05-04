---
layout: post
title: "kamal-backup: Scheduled Rails Backups for Kamal Apps"
date: 2026-05-05
description: "One Kamal accessory for encrypted Rails database and Active Storage backups, restore drills, and redacted evidence for security reviews."
tags: [Ruby, Rails, Kamal, Backups, Open Source]
image: /images/kamal-backup.png
---
I released [kamal-backup](https://kamal-backup.dev) today.

I run [Chat with Work][] on Kamal, and I needed backups. There are already Kamal accessories for database backups. None of them also back up Active Storage. None use restic, so encryption, deduplication, and repository checks are on you. None ship a CLI with restores and drills. None produce evidence you can hand a security reviewer.

So I built one.

## A gem and a Docker image

`kamal-backup` is two pieces: a Ruby gem you add to your Rails app, and a Docker image you boot as a Kamal accessory. They point at a restic repository you bring yourself.

The gem is your CLI. Local commands run directly on your machine using restic. Production-side commands shell out through Kamal into the accessory. The same `kamal-backup` binary covers setup (`init`, `validate`), on-demand operations (`backup`, `list`, `check`), data movement (`restore local`, `restore production`), verification (`drill local`, `drill production`), and audit (`evidence`).

The Docker image (`ghcr.io/crmne/kamal-backup`) ships with `restic`, `pg_dump`, `mariadb-dump`/`mysqldump`, and `sqlite3` baked in. The default container command is `kamal-backup schedule`, a loop that fires every `backup_schedule_seconds` and writes one database snapshot and one Active Storage file snapshot per run.

The restic repository is where the encrypted snapshots end up: S3-compatible object storage, a restic REST server, or a filesystem path. `kamal-backup` points at it. It doesn't run it for you.

## Why restic

I didn't want to invent a backup format, and I didn't want to bolt encryption and deduplication onto shell scripts. Restic does what I needed:

- encrypted repositories by default;
- a tag system, so the database dump and the Active Storage tree from the same run share a `run:<timestamp>` and pair up at restore time;
- deduplication across runs, so a year of daily backups doesn't grow linearly;
- `restic forget --prune` for retention;
- `restic check` for repository health;
- S3-compatible storage, a restic REST server, or a local filesystem path, so you host the repository wherever fits.

It's a single binary that drops cleanly into a Docker image, alongside the database client tools. Nothing extra to install on the Rails host. `kamal-backup` is the Rails- and Kamal-shaped layer on top, and restic does the cryptography, the storage, and the integrity checks.

## Setting it up

Add the gem in development:

```ruby
# Gemfile
group :development do
  gem "kamal-backup"
end
```

Run `init`. It creates `config/kamal-backup.yml` and prints an accessory block you paste into your Kamal deploy config:

```sh
bundle install
bundle exec kamal-backup init
```

`config/kamal-backup.yml` holds the backup settings:

```yaml
accessory: backup
app_name: chatwithwork
database_adapter: postgres
database_url: postgres://chatwithwork@chatwithwork-db:5432/chatwithwork_production
backup_paths:
  - /data/storage
restic_repository: s3:https://s3.example.com/chatwithwork-backups
restic_init_if_missing: true
backup_schedule_seconds: 86400
```

Kamal mounts that file read-only into the accessory, so the accessory block in `config/deploy.yml` stays small. Only secrets live in `env`:

```yaml
accessories:
  backup:
    image: ghcr.io/crmne/kamal-backup:latest
    host: chatwithwork.com
    files:
      - config/kamal-backup.yml:/app/config/kamal-backup.yml:ro
    env:
      secret:
        - PGPASSWORD
        - RESTIC_PASSWORD
        - AWS_ACCESS_KEY_ID
        - AWS_SECRET_ACCESS_KEY
    volumes:
      - "chatwithwork_storage:/data/storage:ro"
      - "chatwithwork_backup_state:/var/lib/kamal-backup"
```

Validate, boot, and watch the logs:

```sh
bundle exec kamal-backup validate
bin/kamal accessory boot backup
bin/kamal accessory logs backup
```

`validate` catches missing required settings before the accessory has to be running. Once it's up, the container loops on `kamal-backup schedule`.

Then run the first backup and print evidence:

```sh
bundle exec kamal-backup backup
bundle exec kamal-backup list
bundle exec kamal-backup evidence
```

No cron glue. No separate backup host. No "remember to install restic on production." The accessory image already has it.

## Rails data, not just a database dump

A Rails app has two things worth backing up: the database, and file-backed Active Storage. `kamal-backup` handles both.

Postgres uses `pg_dump`. MySQL and MariaDB use `mariadb-dump` or `mysqldump`. SQLite uses `sqlite3 .backup`. File-backed Active Storage uses `restic backup` from mounted volumes.

Each run writes one database snapshot and one file snapshot, both tagged with `app:<name>`, `type:database` or `type:files`, and the same `run:<timestamp>`. You pair them at restore time using that timestamp.

If your app stores Active Storage blobs directly in S3, there's no mounted path for `backup_paths` to capture. `kamal-backup` still covers the database. The S3 side is on your bucket lifecycle and replication settings.

## Restores are part of the product

The backup script is the easy part. The restore path is where most setups fail.

So `kamal-backup` ships with restore commands:

```sh
bundle exec kamal-backup restore local
bundle exec kamal-backup restore production
```

`restore local` pulls a production backup down to your laptop. Useful when you want to inspect real data, reproduce a production bug, or prove the backup actually comes back.

`restore production` prompts before it overwrites anything. Destructive restore commands should be boring, not casual.

## Restore drills

The command I care about most is `drill`.

```sh
bundle exec kamal-backup drill local \
  --check "bin/rails runner 'puts User.count'"
```

A drill means: restore, check, record the result.

Two modes:

- `drill local` restores onto your machine and runs an optional check.
- `drill production` restores into scratch production-side targets, never the live database.

That second one matters. For Postgres and MySQL, you give it a scratch database. For SQLite, a scratch file path. For Active Storage, a scratch restore directory. The drill uses production infrastructure, without pointing at live production.

That's the difference between "the backup ran" and "we restored the latest production snapshot into a scratch target on April 30, ran this check, and it passed."

## Evidence for reviews

I went through a security review for [Chat with Work][] this year. The questions were fair:

- What's being backed up?
- Where does it go?
- Is it encrypted?
- When did the last backup run?
- When did the last repository check run?
- When was the last restore drill?
- Can you prove all of that without leaking secrets?

`kamal-backup evidence` prints redacted JSON: current backup settings, latest snapshots, latest restic check, latest restore drill, retention settings, tool versions.

```sh
bundle exec kamal-backup evidence
```

Secrets are redacted. The output is meant to land in an internal ops record or a CASA packet. Not a screenshot of a green cron job. An actual evidence packet.

## Try it

```ruby
# Gemfile
gem "kamal-backup"
```

Docs at [kamal-backup.dev](https://kamal-backup.dev), source on [GitHub](https://github.com/crmne/kamal-backup).

[Chat with Work]: https://chatwithwork.com
