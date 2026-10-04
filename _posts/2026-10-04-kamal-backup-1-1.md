---
layout: post
title: "kamal-backup 1.1: Grab a Database Dump Without Restoring Anything"
date: 2026-10-04
description: "kamal-backup 1.1 adds a dump command that pulls one database dump out of your Kamal backups over SSH, and fixes restoring a specific snapshot."
tags: [Ruby, Rails, Kamal, Backups, Open Source]
image: /images/kamal-backup.png
sendfox_campaign_id: 3055093
---
[kamal-backup](https://kamal-backup.dev) 1.1 adds `dump`, which downloads one database dump from your backups without running a restore:

```sh
bundle exec kamal-backup dump latest -o tmp/app.pgdump
```

It works with PostgreSQL, MySQL, MariaDB, and SQLite. Use it to look at production data locally, to give someone a dump to debug against, or to load a backup into a tool that expects a plain dump file. Before 1.1, that meant restoring somewhere first or running restic by hand inside the accessory.

## How It Works

`dump` talks to the backup accessory over SSH, with the same user, port, proxy, and keys Kamal already uses from `config/deploy.yml`. The accessory reads its own mounted repository config, so your restic credentials never show up on the SSH command line.

`latest` means the newest database snapshot. An ID from `kamal-backup list` gives you the dump from that exact backup run. If you back up more than one database, pick one with `--database NAME`. It won't overwrite an existing file unless you confirm or pass `--yes`.

It only covers databases. For Active Storage files, use `restore` or `drill`.

Thanks to [@pkayokay](https://github.com/pkayokay), who built it ([#27](https://github.com/crmne/kamal-backup/pull/27)).

## Two Fixes

**Restoring a specific snapshot ID works.** Each backup writes one snapshot per database and one for files. On 1.0, `restore` and `drill` with an ID from `list` found that ID for one part and failed on the other. Only `latest` worked. Now every part resolves from the same backup run, and if that run is incomplete, kamal-backup stops before touching anything. Thanks to [@maciej-sokolowski](https://github.com/maciej-sokolowski) for reporting it ([#23](https://github.com/crmne/kamal-backup/issues/23)).

That was a bad bug to have in a tool built around [restores](/kamal-backup-1-0/), and I'm glad it was reported.

**SSH proxies work.** If your `config/deploy.yml` sets `ssh.proxy` or `ssh.proxy_command`, every remote command used to fail, because Kamal passes them as Ruby objects that kamal-backup couldn't read. 1.1 reads them.

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
