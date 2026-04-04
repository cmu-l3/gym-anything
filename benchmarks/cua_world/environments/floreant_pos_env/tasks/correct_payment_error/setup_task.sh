#!/bin/bash
echo "=== Setting up correct_payment_error task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# Restore clean database to ensure consistent starting state
kill_floreant
sleep 1

DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -n "$DB_POSDB" ] && [ -d /opt/floreantpos/posdb_backup ]; then
    echo "Restoring database from backup..."
    rm -rf "$DB_POSDB"
    cp -r /opt/floreantpos/posdb_backup "$DB_POSDB"
    chown -R ga:ga "$DB_POSDB"
fi

# Start Floreant POS
# The agent will see the main screen.
start_and_login

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Initial DB transaction count (approximate, for diffing later)
# We can't easily query live embedded Derby, so we rely on timestamps in export_result.sh
echo "0" > /tmp/initial_tx_count.txt

echo "=== Setup complete ==="