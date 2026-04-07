#!/bin/bash
echo "=== Exporting incident_event_annotation_dashboard result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/incident_event_annotation_dashboard_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/incident_event_annotation_dashboard_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/incident_event_annotation_dashboard_start_ts 2>/dev/null || echo "0")

# Write a Python script to a temp file, then copy into container and execute.
# This avoids heredoc-via-SSH issues.
rm -f /tmp/incident_event_annotation_dashboard_export_script.py 2>/dev/null || true

cat > /tmp/incident_event_annotation_dashboard_export_script.py << 'PYSCRIPT'
import sqlite3, json, sys

output_file = '/tmp/incident_event_annotation_dashboard_dashboards.json'

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
docker cp /tmp/incident_event_annotation_dashboard_export_script.py graphite:/tmp/incident_event_annotation_dashboard_export_script.py 2>/dev/null
docker exec graphite python3 /tmp/incident_event_annotation_dashboard_export_script.py 2>&1
docker cp graphite:/tmp/incident_event_annotation_dashboard_dashboards.json /tmp/incident_event_annotation_dashboard_dashboards.json 2>/dev/null || true

# Package final result, pulling both the SQLite dashboards and the API events
python3 << EOF
import json
import urllib.request

task_start = ${TASK_START}

try:
    with open('/tmp/incident_event_annotation_dashboard_dashboards.json') as f:
        dashboards = json.load(f)
except Exception as e:
    dashboards = {"load_error": str(e)}

try:
    req = urllib.request.urlopen("http://localhost/events/get_data?tags=mitigation_applied")
    events = json.loads(req.read().decode('utf-8'))
except Exception as e:
    events = {"api_error": str(e)}

result = {
    "task_start": task_start,
    "dashboards": dashboards,
    "events": events
}

with open('/tmp/incident_event_annotation_dashboard_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/incident_event_annotation_dashboard_result.json")
EOF

echo "=== Export complete ==="