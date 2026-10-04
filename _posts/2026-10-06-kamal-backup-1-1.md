---
layout: post
title: "kamal-backup 1.1: Grab a Database Dump Without Restoring Anything"
date: 2026-10-06
description: "kamal-backup 1.1 adds a dump command that pulls one database dump out of your Kamal backups over SSH, and fixes restoring a specific snapshot."
tags: [Ruby, Rails, Kamal, Backups, Open Source]
image: /images/kamal-backup.png
---
Sometimes you don't want a restore. You want the dump.

You want to poke at last night's production data on your laptop, hand a dump to whoever is debugging that one weird customer, or load it into a tool that only speaks `pg_restore`. Until now, kamal-backup made you restore somewhere first, or go spelunking inside the accessory for restic.

[kamal-backup](https://kamal-backup.dev) 1.1 adds `dump`:

```sh
bundle exec kamal-backup dump latest -o tmp/app.pgdump
```

That's it. From your app checkout, it streams one database dump out of your backups and writes it to the file you named. PostgreSQL, MySQL, MariaDB, or SQLite.

## How It Works

`dump` talks to the backup accessory over SSH, with the same user, port, proxy, and keys Kamal already uses from `config/deploy.yml`. The accessory reads its own mounted repository config, so your restic credentials never show up on the SSH command line.

`latest` means the newest database snapshot. An ID from `kamal-backup list` gives you the dump from that exact backup run. If you back up more than one database, pick one with `--database NAME`. And it won't overwrite an existing file unless you confirm or pass `--yes`, because nobody needs a surprise at the end of a long download.

It's database-only. Your Active Storage files stay where they are; for those, you still want `restore` or `drill`.

Thanks to [@pkayokay](https://github.com/pkayokay), who built it ([#27](https://github.com/crmne/kamal-backup/pull/27)).

## Two Fixes

**Restoring a specific snapshot works again.** Each backup writes one snapshot per database and one for files. On 1.0, `restore` and `drill` with an ID from `list` resolved that ID for one part and then failed on the other. `latest` worked, which is why it hid. Now every part resolves from the same backup run, and if that run is incomplete, kamal-backup stops before touching anything. Thanks to [@maciej-sokolowski](https://github.com/maciej-sokolowski) for reporting it ([#23](https://github.com/crmne/kamal-backup/issues/23)).

For a tool whose whole pitch is that [a backup is only real after you restore it](/kamal-backup-1-0/), that one stung.

**SSH proxies work.** If your `config/deploy.yml` sets `ssh.proxy` or `ssh.proxy_command`, every remote command used to fail, because Kamal hands those over as Ruby objects kamal-backup couldn't read. Now it can.

## Upgrade

```ruby
gem "kamal-backup", "~> 1.1"
```

The accessory image is `ghcr.io/crmne/kamal-backup:1.1.0`, and `latest` points to it. Update the gem and the accessory together, since remote commands refuse to run when their versions drift:

```sh
bundle update kamal-backup
bin/kamal accessory reboot backup
```

New here? kamal-backup runs encrypted restic backups of your Rails database and Active Storage files as a Kamal accessory, and treats the restore as the part worth testing. I called it 1.0 after moving a production app to a new server with it. [That story is here](/kamal-backup-1-0/).

The [release notes](https://github.com/crmne/kamal-backup/releases/tag/v1.1.0) have the details, and the [restore guide](https://kamal-backup.dev/restore/) covers every `dump` option.
