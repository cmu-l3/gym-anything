#!/bin/bash
set -e
echo "=== Setting up delete_impound_reason task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Determine correct column name (usually 'reason' or 'name')
# We check if 'reason' column exists, otherwise assume 'name'
COL_CHECK=$(opencad_db_query "SHOW COLUMNS FROM impound_reasons LIKE 'reason'" 2>/dev/null)
if [ -n "$COL_CHECK" ]; then
    COL_NAME="reason"
else
    COL_NAME="name"
fi
echo "$COL_NAME" > /tmp/impound_col_name.txt
echo "Using column name: $COL_NAME"

# 2. Ensure the target record "Obstructing Machinery" exists
# We verify if it exists, if not we insert it.
EXISTS=$(opencad_db_query "SELECT COUNT(*) FROM impound_reasons WHERE \`${COL_NAME}\` = 'Obstructing Machinery'" 2>/dev/null)

if [ "$EXISTS" -eq "0" ]; then
    echo "Injecting target impound reason..."
    opencad_db_query "INSERT INTO impound_reasons (\`${COL_NAME}\`) VALUES ('Obstructing Machinery')"
fi

# 3. Record initial state for verification
INITIAL_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM impound_reasons")
echo "$INITIAL_COUNT" > /tmp/initial_impound_count
echo "Initial count: $INITIAL_COUNT"

# 4. Setup Application State (Login Page)
# Remove Firefox profile locks and relaunch to ensure clean state
rm -f /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox http://localhost &"
sleep 10

# Maximize window
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="