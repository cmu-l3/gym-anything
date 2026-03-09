#!/bin/bash
set -e
echo "=== Setting up create_function task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running and ready
wait_for_orientdb 120

# Ensure demodb exists and has data
# We check hotel count. If low, we assume seed is needed.
HOTEL_COUNT=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM Hotels" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

if [ "$HOTEL_COUNT" -lt 5 ]; then
    echo "Demodb has insufficient data ($HOTEL_COUNT hotels). seeding..."
    python3 /workspace/scripts/seed_demodb.py
fi

# Clean up: Remove function if it already exists from previous run
echo "Removing any pre-existing getAvgHotelStars function..."
orientdb_sql "demodb" "DELETE FROM OFunction WHERE name = 'getAvgHotelStars'" >/dev/null 2>&1 || true

# Clean up: Remove output file
rm -f /home/ga/function_results.txt

# Ensure Firefox is at Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Maximize Firefox
sleep 2
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="