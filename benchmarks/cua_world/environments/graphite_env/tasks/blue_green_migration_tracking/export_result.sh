#!/bin/bash
echo "=== Exporting blue_green_migration_tracking result ==="

# Take final screenshot to capture final state evidence
DISPLAY=:1 scrot /tmp/blue_green_migration_tracking_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/blue_green_migration_tracking_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/blue_green_migration_tracking_start_ts 2>/dev/null || echo "0")

# Write a Python script to a temp file, then copy into container and execute.
# This avoids heredoc-via-SSH formatting issues.
rm -f /tmp/blue_green_migration_tracking_export_script.py 2>/dev/null || true

cat > /tmp/blue_green_migration_tracking_export_script.py << 'PYSCRIPT'
import sqlite3, json, sys

output_file = '/tmp/blue_green_migration_tracking_dashboards.json'

try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    # Verify the table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='dashboard_dashboard'")
    if not cursor.fetchone():
        raise RuntimeError("dashboard_dashboard table not found")
    cursor.execute('SELECT name, state FROM dashboard_dashboard')
    dashboards = {}
    for name, state in cursor.fetchall():
        try:
            dashboards[name] = json.loads(state)
        except Exception as e:
            dashboards[name] = {"parse_error": str(e)}
    conn.close()
    with open(output_file, 'w') as f:
        json.dump(dashboards, f)
    print("Dashboard data written: " + str(len(dashboards)) + " dashboards")
except Exception as e:
    sys.stderr.write("ERROR: " + str(e) + "\n")
    with open(output_file, 'w') as f:
        json.dump({"error": str(e)}, f)
PYSCRIPT

# Copy script into container, execute it, copy result out
docker cp /tmp/blue_green_migration_tracking_export_script.py graphite:/tmp/blue_green_migration_tracking_export_script.py 2>/dev/null
docker exec graphite python3 /tmp/blue_green_migration_tracking_export_script.py 2>&1
docker cp graphite:/tmp/blue_green_migration_tracking_dashboards.json /tmp/blue_green_migration_tracking_dashboards.json 2>/dev/null || true

# Package final result locally
python3 << EOF
import json

task_start = ${TASK_START}

try:
    with open('/tmp/blue_green_migration_tracking_dashboards.json') as f:
        dashboards = json.load(f)
except Exception as e:
    dashboards = {"load_error": str(e)}

result = {
    "task_start": task_start,
    "dashboards": dashboards
}

with open('/tmp/blue_green_migration_tracking_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/blue_green_migration_tracking_result.json")
EOF

echo "=== Export complete ==="