#!/bin/bash
echo "=== Setting up wine_dinner_event_setup task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running Floreant POS instance
kill_floreant
sleep 2

# 2. Restore clean database from backup
# This ensures a deterministic start state regardless of prior runs.
# The agent creates ALL new data (tax, category, group, items, modifiers, order) from scratch.
DB_LIVE=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_LIVE" ]; then
    DB_LIVE="/opt/floreantpos/database/derby-server/posdb"
fi

BACKUP=""
if [ -d "/opt/floreantpos/posdb_backup" ]; then
    BACKUP="/opt/floreantpos/posdb_backup"
elif [ -d "/opt/floreantpos/derby_server_backup" ]; then
    BACKUP="/opt/floreantpos/derby_server_backup"
fi

if [ -n "$BACKUP" ]; then
    echo "Restoring DB from $BACKUP -> $DB_LIVE"
    rm -rf "$DB_LIVE"
    cp -r "$BACKUP" "$DB_LIVE"
    chown -R ga:ga "$(dirname "$DB_LIVE")"
else
    echo "WARNING: No backup found, using existing DB"
fi

# 3. Delete any stale output files BEFORE recording the task start timestamp
rm -f /tmp/wine_dinner_result.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null || true

# 4. Record task start timestamp (used to filter tickets created during this task)
date +%s > /tmp/task_start_time.txt

# 5. Launch Floreant POS and wait for the main terminal screen
start_and_login

# 6. Take initial screenshot for verification
take_screenshot /tmp/task_initial.png

echo "=== wine_dinner_event_setup task setup complete ==="
echo "Agent should see the main POS terminal with DINE IN, TAKE OUT, BACK OFFICE buttons."
echo "Agent must click BACK OFFICE and enter PIN 1111 to begin configuration."
