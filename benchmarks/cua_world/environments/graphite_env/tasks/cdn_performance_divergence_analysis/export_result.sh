#!/bin/bash
echo "=== Exporting cdn_performance_divergence_analysis result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/cdn_performance_divergence_analysis_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/cdn_performance_divergence_analysis_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/cdn_performance_divergence_analysis_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Write a Python script to a temp file, then copy into container and execute.
# This extracts the saved dashboards from the SQLite DB inside the Graphite container.
rm -f /tmp/cdn_performance_divergence_analysis_export_script.py 2>/dev/null || true

cat > /tmp/cdn_performance_divergence_analysis_export_script.py << 'PYSCRIPT'
import sqlite3, json, sys

output_file = '/tmp/cdn_performance_divergence_analysis_dashboards.json'

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
docker cp /tmp/cdn_performance_divergence_analysis_export_script.py graphite:/tmp/cdn_performance_divergence_analysis_export_script.py 2>/dev/null
docker exec graphite python3 /tmp/cdn_performance_divergence_analysis_export_script.py 2>&1
docker cp graphite:/tmp/cdn_performance_divergence_analysis_dashboards.json /tmp/cdn_performance_divergence_analysis_dashboards.json 2>/dev/null || true

# Package final result
python3 << EOF
import json
import os

task_start = ${TASK_START}
task_end = ${TASK_END}

try:
    with open('/tmp/cdn_performance_divergence_analysis_dashboards.json') as f:
        dashboards = json.load(f)
except Exception as e:
    dashboards = {"load_error": str(e)}

result = {
    "task_start": task_start,
    "task_end": task_end,
    "dashboards": dashboards,
    "screenshot_path": "/tmp/cdn_performance_divergence_analysis_end_screenshot.png"
}

with open('/tmp/cdn_performance_divergence_analysis_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/cdn_performance_divergence_analysis_result.json")
EOF

# Ensure appropriate permissions so verifier can read it
chmod 666 /tmp/cdn_performance_divergence_analysis_result.json 2>/dev/null || true

echo "=== Export complete ==="