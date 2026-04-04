#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up export_database task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 120

# Verify demodb exists and has data (Populate if necessary)
# The base environment setup usually handles this, but we double-check here
echo "Verifying demodb is populated..."
HOTEL_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
    
if [ "$HOTEL_COUNT" -lt 5 ]; then
    echo "Demodb seems empty or missing (Hotels count: $HOTEL_COUNT). Running seeder..."
    # If the seeder script exists in scripts, run it
    if [ -f "/workspace/scripts/seed_demodb.py" ]; then
        python3 /workspace/scripts/seed_demodb.py > /tmp/seed.log 2>&1
    fi
fi

# Clean up any previous export artifacts to ensure a clean slate
rm -rf /home/ga/exports 2>/dev/null || true
echo "Cleaned previous exports"

# Ensure Firefox is at Studio home
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 3

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== export_database task setup complete ==="
echo "Task: Export demodb to /home/ga/exports/demodb_export.json.gz"
echo "Server credentials: root / GymAnything123!"
echo "DB credentials: admin / admin"