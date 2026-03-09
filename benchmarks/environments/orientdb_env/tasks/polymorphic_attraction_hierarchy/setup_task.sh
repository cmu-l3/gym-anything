#!/bin/bash
set -e
echo "=== Setting up Polymorphic Attraction Hierarchy Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# === CLEANUP PREVIOUS STATE ===
# Drop Museums class if it exists from a previous run to ensure a clean start
echo "Checking for existing Museums class..."
if orientdb_class_exists "demodb" "Museums"; then
    echo "Museums class found from previous run. Dropping..."
    orientdb_sql "demodb" "DROP CLASS Museums UNSAFE" > /dev/null 2>&1 || true
    sleep 2
fi

# Remove the output file if it exists
rm -f /home/ga/attraction_hierarchy_report.txt

# Record initial counts
INITIAL_ATTRACTIONS=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM Attractions" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
echo "$INITIAL_ATTRACTIONS" > /tmp/initial_attraction_count.txt

# === APP SETUP ===
# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile \
    'http://localhost:2480/studio/index.html' &"
sleep 10

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="