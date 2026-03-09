#!/bin/bash
set -e
echo "=== Setting up task: add_bill_reference ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (both epoch and formatted for SQL)
date +%s > /tmp/task_start_time.txt
date -u +"%Y-%m-%d %H:%M:%S" > /tmp/task_start_time_formatted.txt

# Get database path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism database not found"
    exit 1
fi

# Record initial item counts for anti-gaming verification
INITIAL_COUNT=$(get_item_count)
echo "$INITIAL_COUNT" > /tmp/initial_item_count.txt

# Record initial bill count specifically
# We use sqlite3 in read-only mode to avoid locking if Jurism is running
BILL_COUNT=$(sqlite3 -readonly "$DB_PATH" "SELECT COUNT(*) FROM items i JOIN itemTypes it ON i.itemTypeID = it.itemTypeID WHERE it.typeName = 'bill'" 2>/dev/null || echo "0")
echo "$BILL_COUNT" > /tmp/initial_bill_count.txt

echo "Initial item count: $INITIAL_COUNT"
echo "Initial bill count: $BILL_COUNT"

# Ensure Jurism is running and visible
ensure_jurism_running

# Dismiss any lingering dialogs
wait_and_dismiss_jurism_alerts 15

# Maximize and focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="