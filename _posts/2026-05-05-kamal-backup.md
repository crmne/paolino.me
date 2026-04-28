---
layout: post
title: "kamal-backup: Scheduled Rails Backups for Kamal Apps"
date: 2026-05-05
description: "One Kamal accessory for encrypted Rails database and Active Storage backups, restore drills, and redacted evidence for security reviews."
tags: [Ruby, Rails, Kamal, Backups, Open Source]
image: /images/kamal-backup.png
---
I released [kamal-backup](https://kamal-backup.dev) today.

Kamal made deploying a Rails app to your own server feel boring again. That is the whole point. Build an image, push it, boot it, ship. No platform ceremony. No Kubernetes cosplay. Just a Docker host and a deploy tool that understands what a Rails app needs.

Backups did not get the same treatment.

You can deploy a Rails app with Kamal in an afternoon and still end up with a backup setup that feels like a separate ops project: cron on the host, shell scripts in `/usr/local/bin`, object storage credentials in three places, database dumps that nobody has restored, Active Storage files that might or might not be included, and a security review that asks for evidence stronger than "the job is green."

That gap bothered me. If Kamal is the deployment path, backups should feel like adding one more accessory.

So I built `kamal-backup`.

## One accessory

`kamal-backup` runs as a Kamal accessory. Add the gem locally, generate the config stub, add the accessory to `config/deploy.yml`, and boot it:

```ruby
group :development do
  gem "kamal-backup"
end
```

```sh
bundle install
bundle exec kamal-backup init
bin/kamal accessory boot backup
```

The accessory runs `kamal-backup schedule` by default. Set `BACKUP_SCHEDULE_SECONDS`, point it at a restic repository, mount your Active Storage volume read-only, and it keeps running.

No cron glue. No separate backup host. No "remember to install restic on production." The production image already includes the pieces it needs.

## Rails data, not just a database dump

Most small Rails apps have two important data surfaces:

- the database
- file-backed Active Storage

`kamal-backup` handles both.

PostgreSQL uses `pg_dump`. MySQL and MariaDB use `mariadb-dump` or `mysqldump`. SQLite uses `sqlite3 .backup`. File-backed Active Storage paths are backed up with `restic backup` from mounted volumes.

Each run creates one database snapshot and one file snapshot. Both are tagged with the app name and the same run timestamp, so you can tell which pieces belong together.

Restic handles the storage layer: encryption, deduplication, S3-compatible repositories, restic REST servers, filesystem repositories, retention, prune, and checks. I did not want to invent a backup format. I wanted the Rails/Kamal-shaped layer around a tool that already does the hard part.

## Restores are part of the product

The backup script is the easy part. The restore path is where setups usually rot.

People say "we have backups" when what they mean is "a command exits zero every night." That is not the same thing. A backup you have not restored is a theory.

`kamal-backup` has restore commands built in:

```sh
bundle exec kamal-backup -d production restore local latest
bundle exec kamal-backup -d production restore production latest
```

`restore local` pulls production backups into your local Rails app. That is useful when you need to inspect real data, reproduce a production issue, or just prove that the backup can actually come back.

`restore production` is deliberately explicit and prompts before overwriting production. Destructive restore commands should be boring, not casual.

## Restore drills

The command I care about most is `drill`.

```sh
bundle exec kamal-backup -d production drill local latest \
  --check "bin/rails runner 'puts User.count'"
```

A drill means: restore, check, record the result.

There are two modes:

- `drill local` restores onto your machine and runs an optional verification command.
- `drill production` restores into scratch production-side targets, not the live production database.

That second one matters. For PostgreSQL and MySQL, you pass a scratch database. For SQLite, you pass a scratch file path. For Active Storage, you pass a scratch restore path. The drill uses production infrastructure, but it does not quietly point back at live production.

This is the difference between "our backup job ran" and "we restored the latest production snapshot into a scratch target on April 30, ran this check, and it passed."

## Evidence for reviews

I built this while dealing with the kind of security review that does not accept vibes.

Reviewers ask reasonable questions:

- What is being backed up?
- Where does it go?
- Is it encrypted?
- When did the last backup run?
- When did the last repository check run?
- When was the last restore drill?
- Can you prove it without leaking secrets?

`kamal-backup evidence` prints redacted JSON with the current backup settings, latest snapshots, latest restic check, latest restore drill, retention settings, and tool versions:

```sh
bundle exec kamal-backup -d production evidence
```

Secrets are redacted. The output is meant to be attached to internal ops records or security reviews like CASA. Not a screenshot of a green cron job. An actual evidence packet.

## What it looks like

A minimal accessory looks like this:

```yaml
accessories:
  backup:
    image: ghcr.io/crmne/kamal-backup:latest
    host: app.example.com
    env:
      clear:
        APP_NAME: myapp
        DATABASE_ADAPTER: postgres
        DATABASE_URL: postgres://myapp@myapp-db:5432/myapp_production
        BACKUP_PATHS: /data/storage
        RESTIC_REPOSITORY: s3:https://s3.example.com/myapp-backups
        RESTIC_INIT_IF_MISSING: "true"
        BACKUP_SCHEDULE_SECONDS: "86400"
      secret:
        - PGPASSWORD
        - RESTIC_PASSWORD
        - AWS_ACCESS_KEY_ID
        - AWS_SECRET_ACCESS_KEY
    volumes:
      - "myapp_storage:/data/storage:ro"
      - "myapp_backup_state:/var/lib/kamal-backup"
```

Then the local gem becomes the operator interface:

```sh
bundle exec kamal-backup -d production backup
bundle exec kamal-backup -d production list
bundle exec kamal-backup -d production check
bundle exec kamal-backup -d production evidence
```

The `-d` and `-c` flags work the way they do in Kamal. Production-side commands shell out through Kamal to the backup accessory. Local restore and local drill run on your machine.

## Try it

Install the gem:

```ruby
gem "kamal-backup", "~> 0.1"
```

Read the docs at [kamal-backup.dev](https://kamal-backup.dev), or browse the source on [GitHub](https://github.com/crmne/kamal-backup).

If you already deploy with Kamal, backups should not be a second system you operate next to your app. They should be one accessory, one restic repository, one restore path you actually practice, and one command that tells you whether the whole thing is still true.
