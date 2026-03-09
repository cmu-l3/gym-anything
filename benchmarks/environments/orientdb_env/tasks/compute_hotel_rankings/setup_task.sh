#!/bin/bash
echo "=== Setting up compute_hotel_rankings task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# Check/Reset state: Drop ImpactScore property if it exists from previous run
echo "Checking for existing ImpactScore property..."
SCHEMA_JSON=$(orientdb_query "demodb" "SELECT FROM (SELECT expand(properties) FROM (SELECT expand(classes) FROM metadata:schema) WHERE name = 'Hotels') WHERE name = 'ImpactScore'")
PROP_EXISTS=$(echo "$SCHEMA_JSON" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data['result']))" 2>/dev/null || echo "0")

if [ "$PROP_EXISTS" -gt "0" ]; then
    echo "Dropping existing ImpactScore property..."
    orientdb_sql "demodb" "DROP PROPERTY Hotels.ImpactScore" > /dev/null 2>&1 || true
    sleep 2
fi

# Ensure Firefox is open to Studio
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="