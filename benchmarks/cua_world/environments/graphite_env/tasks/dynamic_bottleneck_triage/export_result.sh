#!/bin/bash
echo "=== Exporting dynamic_bottleneck_triage result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/dynamic_bottleneck_triage_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/dynamic_bottleneck_triage_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/dynamic_bottleneck_triage_start_ts 2>/dev/null || echo "0")

# Write a Python script to extract dashboard JSON from Graphite's internal SQLite DB.
# We do this from inside the container to avoid heredoc/stdin streaming issues with docker exec.
rm -f /tmp/dynamic_bottleneck_triage_export_script.py 2>/dev/null || true

cat > /tmp/dynamic_bottleneck_triage_export_script.py << 'PYSCRIPT'
import sqlite3, json, sys

output_file = '/tmp/dynamic_bottleneck_triage_dashboards.json'

try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
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
docker cp /tmp/dynamic_bottleneck_triage_export_script.py graphite:/tmp/dynamic_bottleneck_triage_export_script.py 2>/dev/null
docker exec graphite python3 /tmp/dynamic_bottleneck_triage_export_script.py 2>&1
docker cp graphite:/tmp/dynamic_bottleneck_triage_dashboards.json /tmp/dynamic_bottleneck_triage_dashboards.json 2>/dev/null || true

# Package final result with timestamps
python3 << EOF
import json

task_start = ${TASK_START}

try:
    with open('/tmp/dynamic_bottleneck_triage_dashboards.json') as f:
        dashboards = json.load(f)
except Exception as e:
    dashboards = {"load_error": str(e)}

result = {
    "task_start": task_start,
    "dashboards": dashboards
}

with open('/tmp/dynamic_bottleneck_triage_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/dynamic_bottleneck_triage_result.json")
EOF

echo "=== Export complete ==="