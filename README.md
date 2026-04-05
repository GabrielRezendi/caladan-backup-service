# caladan-backup-service

Systemd service that creates a full system backup as an ISO file, run daily via a timer. Keeps the last 7 backups and automatically removes older ones.

## How it works

1. Creates a compressed tar archive of the root filesystem (excluding pseudo-filesystems, tmp, caches, etc.)
2. Packages the archive and a manifest into an ISO file
3. Saves the ISO to `/mnt/storage1/backups/`
4. Rotates old backups, retaining only the last 7

Backups are named `backup_<hostname>_<YYYYMMDD_HHMMSS>.iso` and logged to `/var/log/backup-iso.log`.

## Requirements

- `tar`
- `xorrisofs` (from the `xorriso` package)
- `/mnt/storage1` must be mounted before the service starts
- At least 20 GB free on `/mnt/storage1`

## Installation

```bash
cp backup-iso.service /etc/systemd/system/
cp backup-iso.timer  /etc/systemd/system/
cp backup-iso.sh     /git/caladan-backup-service/
chmod +x /git/caladan-backup-service/backup-iso.sh
systemctl daemon-reload
systemctl enable --now backup-iso.timer
```

## Usage

Run a backup manually:

```bash
systemctl start backup-iso.service
```

Check status / logs:

```bash
systemctl status backup-iso.service
journalctl -u backup-iso.service
tail -f /var/log/backup-iso.log
```

Check the timer:

```bash
systemctl list-timers backup-iso.timer
```

## Schedule

Runs daily at **02:00 AM**. If a run was missed (e.g. machine was off), it will catch up on next boot (`Persistent=true`), with a randomized delay of up to 5 minutes.

## Restore

```bash
tar -xzpf system.tar.gz -C /mnt/restore --numeric-owner
```
