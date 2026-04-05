#!/bin/bash
# Full system backup to ISO — keeps last 7 daily backups
# Saves to /mnt/storage/backups/

set -euo pipefail

BACKUP_DIR="/mnt/storage1/backups"
HOSTNAME_STR=$(hostname -s)
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="backup_${HOSTNAME_STR}_${DATE}"
STAGING_DIR="/tmp/backup_staging_$$"
TAR_FILE="${STAGING_DIR}/system.tar.gz"
ISO_FILE="${BACKUP_DIR}/${BACKUP_NAME}.iso"
LOG_FILE="/var/log/backup-iso.log"
RETENTION_DAYS=7

# Redirect all output to log with timestamps
exec > >(while IFS= read -r line; do echo "$(date '+%Y-%m-%d %H:%M:%S') $line"; done | tee -a "$LOG_FILE") 2>&1

log() { echo "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

log "=== Backup started: ${BACKUP_NAME} ==="

# Ensure backup destination exists
if ! mountpoint -q /mnt/storage 2>/dev/null && [[ ! -d /mnt/storage/backups ]]; then
    die "/mnt/storage is not mounted or /mnt/storage/backups does not exist"
fi
mkdir -p "$BACKUP_DIR"

# Check available space (need at least 20G free)
AVAIL_KB=$(df -k "$BACKUP_DIR" | awk 'NR==2 {print $4}')
if [[ $AVAIL_KB -lt 20971520 ]]; then
    die "Less than 20 GB free on $BACKUP_DIR (${AVAIL_KB} KB available)"
fi

# Create staging area
mkdir -p "$STAGING_DIR"
trap 'log "Cleaning up staging area..."; rm -rf "$STAGING_DIR"' EXIT

# Directories to exclude from the tar archive
EXCLUDES=(
    --exclude=/proc
    --exclude=/sys
    --exclude=/dev
    --exclude=/run
    --exclude=/tmp
    --exclude=/mnt
    --exclude=/media
    --exclude=/lost+found
    --exclude=/var/tmp
    --exclude=/var/cache/apt/archives
    --exclude=/var/log/journal
    --exclude="$STAGING_DIR"
    --exclude=/tmp/backup_staging_*
)

log "Creating tar archive of filesystem..."
tar \
    "${EXCLUDES[@]}" \
    --one-file-system \
    --ignore-failed-read \
    --warning=no-file-changed \
    -czpf "$TAR_FILE" \
    / 2>&1 | grep -v "^tar:" || true

TAR_SIZE=$(du -sh "$TAR_FILE" | cut -f1)
log "Archive created: ${TAR_SIZE}"

# Write a manifest with system info
cat > "${STAGING_DIR}/BACKUP_INFO.txt" <<EOF
Backup created:  $(date)
Hostname:        $(hostname -f)
Kernel:          $(uname -r)
OS:              $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo unknown)
Archive size:    ${TAR_SIZE}
Root filesystem: $(df -h / | awk 'NR==2')
Restore command: tar -xzpf system.tar.gz -C /mnt/restore --numeric-owner
EOF

log "Building ISO..."
xorrisofs \
    -o "$ISO_FILE" \
    -V "BACKUP_${DATE}" \
    -r \
    -J \
    "$STAGING_DIR"

ISO_SIZE=$(du -sh "$ISO_FILE" | cut -f1)
log "ISO created: $ISO_FILE (${ISO_SIZE})"

# Rotate old backups — keep only last RETENTION_DAYS
log "Rotating old backups (keeping last ${RETENTION_DAYS})..."
mapfile -t OLD_BACKUPS < <(
    find "$BACKUP_DIR" -maxdepth 1 -name "backup_${HOSTNAME_STR}_*.iso" \
        -printf '%T@ %p\n' | sort -n | head -n "-${RETENTION_DAYS}" | awk '{print $2}'
)

if [[ ${#OLD_BACKUPS[@]} -gt 0 ]]; then
    for f in "${OLD_BACKUPS[@]}"; do
        log "Removing old backup: $(basename "$f")"
        rm -f "$f"
    done
else
    log "No old backups to remove."
fi

# List current backups
log "Current backups in ${BACKUP_DIR}:"
find "$BACKUP_DIR" -maxdepth 1 -name "backup_${HOSTNAME_STR}_*.iso" \
    -printf '  %f  (%s bytes)\n' | sort

log "=== Backup completed successfully ==="
