#!/bin/bash
set -e
echo "=== Setting up fix_author_field_structure task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access (DB is locked while Jurism runs)
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Ensure references are loaded
echo "Ensuring legal references are loaded..."
python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null || echo "Injection script returned error (might be benign)"

# MODIFY DATABASE: "Break" the specific authors by setting them to single-field mode
# This simulates a bad import where personal names were interpreted as institutional names
echo "Modifying database to corrupt author name structures..."

sqlite3 "$JURISM_DB" <<EOF
-- Fix Henry P. Monaghan -> Single Field 'Henry P. Monaghan'
UPDATE creators 
SET fieldMode = 1, 
    lastName = 'Henry P. Monaghan', 
    firstName = '' 
WHERE lastName = 'Monaghan' AND firstName = 'Henry P.';

-- Fix Ronald D. Poe -> Single Field 'Ronald D. Poe'
UPDATE creators 
SET fieldMode = 1, 
    lastName = 'Ronald D. Poe', 
    firstName = '' 
WHERE lastName = 'Poe' AND firstName = 'Ronald D.';
EOF

echo "Database modification complete."

# Relaunch Jurism so the agent sees the "broken" state
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism to load and dismiss any in-app alert dialogs
wait_and_dismiss_jurism_alerts 45

# Maximize and focus Jurism window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take initial screenshot showing the library list
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="