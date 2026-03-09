#!/bin/bash
set -e
echo "=== Setting up shortest_path_social_network task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 120

# Check if demodb exists and has data
if ! orientdb_db_exists "demodb"; then
    echo "Creating and seeding demodb..."
    python3 /workspace/scripts/seed_demodb.py
else
    # Verify data volume
    PROFILE_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Profiles" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
    
    if [ "$PROFILE_COUNT" -lt 10 ]; then
        echo "Insufficient data in demodb, re-seeding..."
        python3 /workspace/scripts/seed_demodb.py
    fi
fi

# Ensure Firefox is open at OrientDB Studio
echo "Ensuring Firefox is open..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 5

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Clean up previous results
rm -f /home/ga/shortest_path_results.json

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="