#!/bin/bash
echo "=== Setting up Country Dashboard Materialization Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running
wait_for_orientdb 60

# --- CLEANUP PREVIOUS STATE ---
# We must ensure the CountryDashboard class DOES NOT exist at start
echo "Ensuring clean state (dropping CountryDashboard if exists)..."
CLASS_EXISTS=$(orientdb_class_exists "demodb" "CountryDashboard"; echo $?)

if [ "$CLASS_EXISTS" -eq 0 ]; then
    echo "Class CountryDashboard found, dropping..."
    orientdb_sql "demodb" "DROP CLASS CountryDashboard UNSAFE" > /dev/null 2>&1 || true
    sleep 2
fi

# Verify cleanup
CLASS_EXISTS_AFTER=$(orientdb_class_exists "demodb" "CountryDashboard"; echo $?)
if [ "$CLASS_EXISTS_AFTER" -eq 0 ]; then
    echo "ERROR: Failed to clean up CountryDashboard class. Task cannot start cleanly."
    exit 1
fi

# Ensure Firefox is at Studio
echo "Launching Firefox to OrientDB Studio..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="