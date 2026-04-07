#!/bin/bash
echo "=== Setting up delete_warrant_type task ==="

source /workspace/scripts/task_utils.sh

# 1. Detect the correct table for warrant types
# OpenCAD schemas vary (warrant_types, warrants_types, other_warrant_types)
echo "Detecting warrant types table..."
TABLE_NAME=$(docker exec opencad-db mysql -u opencad -popencadpass opencad -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema='opencad' AND table_name LIKE '%warrant%type%' LIMIT 1")

if [ -z "$TABLE_NAME" ]; then
    echo "ERROR: Could not find warrant types table. Defaulting to 'warrant_types'."
    TABLE_NAME="warrant_types"
fi
echo "$TABLE_NAME" > /tmp/warrant_table_name.txt
echo "Using table: $TABLE_NAME"

# 2. Inject the target data "Civil Contempt"
# We check if it exists first to avoid duplicates if constraints are missing
TARGET="Civil Contempt"
EXISTS_COUNT=$(docker exec opencad-db mysql -u opencad -popencadpass opencad -N -e "SELECT COUNT(*) FROM $TABLE_NAME WHERE warrant_type='$TARGET'")

if [ "$EXISTS_COUNT" -eq "0" ]; then
    echo "Injecting target record: '$TARGET'..."
    docker exec opencad-db mysql -u opencad -popencadpass opencad -e "INSERT INTO $TABLE_NAME (warrant_type) VALUES ('$TARGET')"
else
    echo "Target record '$TARGET' already exists."
fi

# 3. Record Initial State for Anti-Gaming
INITIAL_COUNT=$(docker exec opencad-db mysql -u opencad -popencadpass opencad -N -e "SELECT COUNT(*) FROM $TABLE_NAME")
echo "$INITIAL_COUNT" > /tmp/initial_warrant_count.txt
date +%s > /tmp/task_start_time.txt

echo "Initial count: $INITIAL_COUNT"

# 4. Prepare Browser (Login Page)
# Remove locks to ensure clean start
rm -f /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
DISPLAY=:1 firefox "http://localhost/login.php" &
sleep 10

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="