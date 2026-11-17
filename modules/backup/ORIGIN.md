# Backup module

Every night, a [restic](https://github.com/restic/restic) backup (BSD-2-Clause, image pinned in `versions.lock`) of:

- the data folder (`ALICE_DATA_DIR`), without the models, which download again;
- `machine.env` and `/etc/alice-harness`;
- any path listed in `ALICE_BACKUP_EXTRA` (a vault's data, a tunnel's settings, your own files).

SQLite databases (Open WebUI, n8n, ntfy, Home Assistant) are first copied with the SQLite backup API into
`ALICE_DATA_DIR/backup/sqlite/<original path>`, and those copies are what the backup keeps: a database copied while it is
written can be unreadable. Kept: 7 daily, 4 weekly and 6 monthly backups.

The repository is `ALICE_BACKUP_DIR` (default `/var/backups/<prefix>`), outside the data folder, so uninstalling with
the data keeps it. It is encrypted with `/etc/alice-harness/<prefix>-backup.key`, created at the first run: **keep a copy
of that key off the machine**. A backup on the same disk protects against mistakes, a bad update or a corrupted
database, not against the disk dying; copy the repository elsewhere for that (restic `copy`, or any file sync).

The hourly health check alerts when the last backup is more than two days old.

Restore (as root): list the backups with `bash modules/backup/restic.sh snapshots`, then restore into a folder of
your choice (the helper mounts read-only, so run the image directly):

```
docker run --rm -e RESTIC_REPOSITORY=/repo -e RESTIC_PASSWORD_FILE=/key -v /var/backups/<prefix>:/repo \
  -v /etc/alice-harness/<prefix>-backup.key:/key:ro -v /tmp/restore:/restore <RESTIC_IMAGE from versions.lock> \
  restore latest --target /restore
```
