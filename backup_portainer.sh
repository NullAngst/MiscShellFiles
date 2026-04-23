#!/bin/bash

# Configuration
BACKUP_ROOT="/mnt/media/backups"
CURRENT_DATE=$(date +%Y.%m.%d)
DEST_DIR="$BACKUP_ROOT/$CURRENT_DATE"

# Sources to backup
# I removed the trailing /_data from the portainer path so the
# resulting folder in your backup is named 'portainer_data'
SOURCES=(
    "/home/tyler"
    "/opt"
)

# 1. Safety Check: Root required for /opt and /var/lib/docker
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root to access Docker volumes."
  exit 1
fi

# 2. Create the daily directory
mkdir -p "$DEST_DIR"

# 3. Run Rsync
# -v: verbose
# -p: perms
# -a: archive (implies -rlptgoD)
# -r: recursive
# -t: times
# -l: links
for src in "${SOURCES[@]}"; do
    echo "Starting backup for: $src"
    rsync -vpartl "$src" "$DEST_DIR/"
done

# 4. Retention Policy: Delete backups older than 7 days
# -mtime +6 targets files modified 7 days ago or more.
echo "Pruning backups older than 7 days..."
find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" -mtime +6 -exec rm -rf {} +

echo "Backup and cleanup complete."
