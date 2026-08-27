---
layout: post
title: "kamal-backup 1.0: A Backup Is Only Real After You Restore It"
seo_title: "kamal-backup 1.0: Rails Backups and Restores for Kamal"
date: 2026-08-27
description: "kamal-backup 1.0 brings exact Rails restores, restore drills, and PostgreSQL, MySQL, MariaDB, SQLite, SFTP, and rclone support to Kamal."
tags: [Ruby, Rails, Kamal, Backups, Open Source]
image: /images/kamal-backup.png
sendfox_campaign_id: 3008757
---
I released [kamal-backup](https://kamal-backup.dev) 1.0 today.

Not because the backup command works. That part worked months ago.

I called it 1.0 because I used it to move [Chat with Work](https://chatwithwork.com), the application that pays my bills, to a new Hetzner instance. The old host took the backup. The new host restored it under a temporary hostname. I opened the real application, checked the real data and files, and only then moved DNS.

A backup is only real after you restore it.

## The migration that made 1.0

The move found two bugs that a green backup log never could.

First, a fresh backup accessory on the new host could start its schedule before the restore and write a perfectly valid, completely empty snapshot into the same repository. Ask for `latest` during the migration and you could restore that one.

Second, Kamal had already run Rails' `db:prepare` on the new host. PostgreSQL's normal `pg_restore --clean` path could not reliably replace that prepared schema when target-only foreign keys got in the way. Drops failed, creates failed because objects still existed, data never loaded, and `pg_restore` could still look more successful than the database it left behind.

Those problems became the restore model in 1.0. A replacement host can boot its accessory with scheduled backups disabled. PostgreSQL restores remove the target's user schemas first, recreate `public`, restore with a client matching the server, and fail if `pg_restore` reports ignored errors.

The workflow is now written down in the [host migration guide](https://kamal-backup.dev/migrating-hosts/): restore under a temporary hostname, verify the application, stop writes to the old host, take and restore a final backup if necessary, then move traffic.

## Exact means exact

A restore should leave the target looking like the snapshot, not like the snapshot layered over whatever happened to be there already.

That promise now applies to every supported database:

- PostgreSQL removes every non-system schema before restoring the custom-format dump.
- MySQL and MariaDB remove existing views, tables, sequences, routines, functions, and events before importing.
- SQLite uses its native `.backup` and `.restore` APIs, checks the downloaded database before touching the target, and runs `quick_check` again afterward.

The file restore runs before the database restore. That matters when a Rails SQLite database and file-backed Active Storage live on the same volume: the clean SQLite backup stays separate from the raw database, WAL, and shared-memory files, and restoring the files cannot delete the database that was just restored.

Production restores require the application, jobs, and other database writers to be stopped. Restore drills use scratch databases, scratch SQLite files, and scratch file paths instead of touching the live targets. The point is not to make destructive operations feel casual. It is to make the safe procedure obvious and repeatable.

## Tested beyond PostgreSQL

The Chat with Work migration was PostgreSQL. I do not have a production MySQL or SQLite migration story to pretend otherwise.

What 1.0 has instead is an exact backup-and-restore matrix that builds the real accessory image and exercises:

- PostgreSQL 14, 15, 16, 17, and 18;
- MySQL 8.0 and 8.4;
- MariaDB 10.11, 11.4, and 11.8;
- SQLite in WAL mode, including backup and restore through restic's rclone backend.

The matrix creates data, views, routines, functions, triggers, events, custom PostgreSQL schemas, and MariaDB sequences. It adds objects that exist only in the restore target, restores the snapshot, and checks that the stored objects work and the target-only objects are gone.

The accessory image ships for amd64 and arm64. It includes matching PostgreSQL clients, the MariaDB client tools used for MySQL and MariaDB, SQLite, restic, rclone, and SSH. Restic's native repositories still work, SFTP works with a dedicated SSH key, and rclone opens the rest of its storage providers without turning kamal-backup into a storage abstraction of its own.

## The same small Kamal accessory

The shape of the project has not changed since [I first released it](/kamal-backup/): a Ruby gem gives your Rails repository a CLI, and a Docker image runs the scheduled backups beside your application as a Kamal accessory.

```ruby
group :development do
  gem "kamal-backup", "~> 1.0"
end
```

```sh
bundle install
bundle exec kamal-backup init
bundle exec kamal-backup validate
bin/kamal accessory boot backup
bundle exec kamal-backup backup --force
bundle exec kamal-backup drill production latest
```

It backs up one or more PostgreSQL, MySQL, MariaDB, or SQLite databases, plus the file paths you explicitly configure for file-backed Active Storage. Restic handles encryption, deduplication, retention, and repository integrity. `kamal-backup evidence` turns the configuration, latest snapshots, checks, drills, retention, and tool versions into redacted JSON for the next person who asks whether the backups actually work.

Version 1.0 does not mean backups are finished. It means the interface and the restore promises are ready to depend on.

Read the [documentation](https://kamal-backup.dev), look through the [restore guide](https://kamal-backup.dev/restore/), and get the source on [GitHub](https://github.com/crmne/kamal-backup).

Then run a restore drill. The green backup log is the beginning of the test, not the end.
