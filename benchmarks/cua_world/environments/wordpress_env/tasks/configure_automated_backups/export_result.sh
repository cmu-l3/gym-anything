#!/bin/bash
echo "=== Exporting configure_automated_backups result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# Check if UpdraftPlus is active
UPDRAFT_ACTIVE="false"
if wp plugin is-active updraftplus --allow-root 2>/dev/null; then
    UPDRAFT_ACTIVE="true"
fi

# Get configured options
INTERVAL=$(wp option get updraft_interval --allow-root 2>/dev/null || echo "")
INTERVAL_DB=$(wp option get updraft_interval_database --allow-root 2>/dev/null || echo "")
RETAIN=$(wp option get updraft_retain --allow-root 2>/dev/null || echo "")
RETAIN_DB=$(wp option get updraft_retain_db --allow-root 2>/dev/null || echo "")
EXCLUDE_UPLOADS=$(wp option get updraft_exclude_uploads --allow-root 2>/dev/null || echo "")

# Find backup files created after task start
UPDRAFT_DIR="/var/www/html/wordpress/wp-content/updraft"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Identify the most recent DB and Uploads backups
DB_BACKUP=$(find "$UPDRAFT_DIR" -name "*db.gz" -type f -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
UPLOADS_BACKUP=$(find "$UPDRAFT_DIR" -name "*uploads.zip" -type f -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)

DB_BACKUP_EXISTS="false"
UPLOADS_BACKUP_EXISTS="false"
UPLOADS_BACKUP_SIZE=0

if [ -n "$DB_BACKUP" ]; then
    DB_MTIME=$(stat -c %Y "$DB_BACKUP" 2>/dev/null || echo "0")
    # Verify backup was generated during the agent session
    if [ "$DB_MTIME" -ge "$TASK_START" ]; then
        DB_BACKUP_EXISTS="true"
    fi
fi

if [ -n "$UPLOADS_BACKUP" ]; then
    UPLOADS_MTIME=$(stat -c %Y "$UPLOADS_BACKUP" 2>/dev/null || echo "0")
    if [ "$UPLOADS_MTIME" -ge "$TASK_START" ]; then
        UPLOADS_BACKUP_EXISTS="true"
        UPLOADS_BACKUP_SIZE=$(stat -c %s "$UPLOADS_BACKUP" 2>/dev/null || echo "0")
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "updraft_active": $UPDRAFT_ACTIVE,
    "settings": {
        "interval": "$(json_escape "$INTERVAL")",
        "interval_db": "$(json_escape "$INTERVAL_DB")",
        "retain": "$(json_escape "$RETAIN")",
        "retain_db": "$(json_escape "$RETAIN_DB")",
        "exclude_uploads": "$(json_escape "$EXCLUDE_UPLOADS")"
    },
    "backups": {
        "db_exists": $DB_BACKUP_EXISTS,
        "uploads_exists": $UPLOADS_BACKUP_EXISTS,
        "uploads_size_bytes": $UPLOADS_BACKUP_SIZE
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/configure_automated_backups_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_automated_backups_result.json 2>/dev/null || true
chmod 666 /tmp/configure_automated_backups_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export completed. Result:"
cat /tmp/configure_automated_backups_result.json