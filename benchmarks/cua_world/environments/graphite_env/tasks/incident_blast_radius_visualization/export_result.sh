#!/bin/bash
echo "=== Exporting incident_blast_radius_visualization result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/incident_blast_radius_visualization_start_ts 2>/dev/null || echo "0")

# Take final screenshot (for VLM and artifact recording)
DISPLAY=:1 scrot /tmp/incident_blast_radius_visualization_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/incident_blast_radius_visualization_end_screenshot.png 2>/dev/null || true

# Check if Firefox/Graphite is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Write a Python script to a temp file, then copy it into the container and execute it.
# This avoids heredoc-via-SSH issues, ensuring clean JSON payload extraction.
rm -f /tmp/incident_blast_radius_visualization_export_script.py 2>/dev/null || true

cat > /tmp/incident_blast_radius_visualization_export_script.py << 'PYSCRIPT'
import sqlite3, json, sys

output_file = '/tmp/incident_blast_radius_visualization_dashboards.json'

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

# Fix the output filename inside the script (in case of replacements)
sed -i "s|/tmp/.*_dashboards.json|/tmp/incident_blast_radius_visualization_dashboards.json|g" /tmp/incident_blast_radius_visualization_export_script.py 2>/dev/null || true

# Copy script into container, execute it, then copy the result payload out
docker cp /tmp/incident_blast_radius_visualization_export_script.py graphite:/tmp/incident_blast_radius_visualization_export_script.py 2>/dev/null
docker exec graphite python3 /tmp/incident_blast_radius_visualization_export_script.py 2>&1
docker cp graphite:/tmp/incident_blast_radius_visualization_dashboards.json /tmp/incident_blast_radius_visualization_dashboards.json 2>/dev/null || true

# Combine all verification data into a single final JSON result for verifier.py
python3 << EOF
import json
import os

task_start = ${TASK_START}
task_end = ${TASK_END}
app_running = ${APP_RUNNING}
screenshot_exists = os.path.exists("/tmp/incident_blast_radius_visualization_end_screenshot.png")

try:
    with open('/tmp/incident_blast_radius_visualization_dashboards.json') as f:
        dashboards = json.load(f)
except Exception as e:
    dashboards = {"load_error": str(e)}

result = {
    "task_start": task_start,
    "task_end": task_end,
    "app_was_running": app_running,
    "screenshot_exists": screenshot_exists,
    "dashboards": dashboards
}

with open('/tmp/incident_blast_radius_visualization_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result successfully written to /tmp/incident_blast_radius_visualization_result.json")
EOF

# Correct permissions to ensure verifier.py can read it
chmod 666 /tmp/incident_blast_radius_visualization_result.json 2>/dev/null || true

echo "=== Export complete ==="