#!/bin/bash
set -e
echo "=== Setting up delete_obsolete_references task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
date '+%Y-%m-%d %H:%M:%S' > /tmp/task_start_iso.txt

source /workspace/scripts/task_utils.sh

# Get database path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Try to find it one more time or fail
    DB_PATH="/home/ga/Jurism/jurism.sqlite"
fi

echo "Using database: $DB_PATH"

# Ensure Jurism is closed for DB operations
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Inject the 10 legal references (using the utility script in the environment)
echo "Injecting legal references..."
python3 /workspace/utils/inject_references.py "$DB_PATH" all 2>/dev/null || echo "Injection script returned error (might be benign)"

# Verify injection and get IDs
echo "Resolving Item IDs..."

# Function to get ID by vague title match
get_id_by_title() {
    local term="$1"
    sqlite3 "$DB_PATH" "SELECT items.itemID FROM items JOIN itemData ON items.itemID = itemData.itemID JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID WHERE fieldID IN (1, 58) AND value LIKE '%${term}%' LIMIT 1"
}

# 1. Target: Obergefell
ID_OBERGEFELL=$(get_id_by_title "Obergefell")
echo "$ID_OBERGEFELL" > /tmp/target_obergefell.id
echo "Obergefell ID: $ID_OBERGEFELL"

# 2. Target: Gideon
ID_GIDEON=$(get_id_by_title "Gideon")
echo "$ID_GIDEON" > /tmp/target_gideon.id
echo "Gideon ID: $ID_GIDEON"

# 3. Target: Poe Article
ID_POE=$(get_id_by_title "Due Process Clause and the Substantive")
echo "$ID_POE" > /tmp/target_poe.id
echo "Poe Article ID: $ID_POE"

# 4. Keep items (Sample check)
ID_BROWN=$(get_id_by_title "Brown v. Board")
ID_MARBURY=$(get_id_by_title "Marbury")
ID_MIRANDA=$(get_id_by_title "Miranda")
ID_NYT=$(get_id_by_title "Sullivan")
ID_TINKER=$(get_id_by_title "Tinker")
ID_HOLMES=$(get_id_by_title "Path of the Law")
ID_MONAGHAN=$(get_id_by_title "Constitutional Fact")

# Save keep IDs to a list for export script to check
cat > /tmp/keep_items.ids << EOF
$ID_BROWN
$ID_MARBURY
$ID_MIRANDA
$ID_NYT
$ID_TINKER
$ID_HOLMES
$ID_MONAGHAN
EOF

# Ensure trash is empty initially
sqlite3 "$DB_PATH" "DELETE FROM deletedItems;" 2>/dev/null || true

# Record initial counts
INITIAL_TOTAL=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "$INITIAL_TOTAL" > /tmp/initial_total_count.txt
echo "Initial total items: $INITIAL_TOTAL"

# Relaunch Jurism
echo "Starting Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_task.log 2>&1 &'

# Wait for window
echo "Waiting for Jurism window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Jurism" > /dev/null; then
        break
    fi
    sleep 1
done

# Dismiss any alerts
wait_and_dismiss_jurism_alerts 30

# Maximize window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 2

# Initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="