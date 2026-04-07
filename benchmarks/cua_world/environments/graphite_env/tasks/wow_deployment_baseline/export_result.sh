#!/bin/bash
echo "=== Exporting wow_deployment_baseline result ==="

# Take a final screenshot of the agent's work
DISPLAY=:1 scrot /tmp/wow_deployment_baseline_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/wow_deployment_baseline_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/wow_deployment_baseline_start_ts 2>/dev/null || echo "0")

# Write a Python script to a temp file to extract the SQLite DB from inside the Graphite container
rm -f /tmp/wow_deployment_baseline_export_script.py 2>/dev/null || true

cat > /tmp/wow_deployment_baseline_export_script.py << 'PYSCRIPT'
import sqlite3, json, sys

output_file = '/tmp/wow_deployment_baseline_dashboards.json'

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

# Execute the script inside the container and bring the result out
docker cp /tmp/wow_deployment_baseline_export_script.py graphite:/tmp/wow_deployment_baseline_export_script.py 2>/dev/null
docker exec graphite python3 /tmp/wow_deployment_baseline_export_script.py 2>&1
docker cp graphite:/tmp/wow_deployment_baseline_dashboards.json /tmp/wow_deployment_baseline_dashboards.json 2>/dev/null || true

# Package the final result with timestamp
python3 << EOF
import json

task_start = ${TASK_START}

try:
    with open('/tmp/wow_deployment_baseline_dashboards.json') as f:
        dashboards = json.load(f)
except Exception as e:
    dashboards = {"load_error": str(e)}

result = {
    "task_start": task_start,
    "dashboards": dashboards
}

with open('/tmp/wow_deployment_baseline_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/wow_deployment_baseline_result.json")
EOF

echo "=== Export complete ==="