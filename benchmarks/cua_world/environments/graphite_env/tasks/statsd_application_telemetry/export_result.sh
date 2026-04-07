#!/bin/bash
echo "=== Exporting statsd_application_telemetry result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/statsd_application_telemetry_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/statsd_application_telemetry_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/statsd_application_telemetry_start_ts 2>/dev/null || echo "0")

# Write a Python script to a temp file, then copy into container and execute.
# This extracts the saved dashboards from Graphite's internal SQLite database.
rm -f /tmp/statsd_application_telemetry_export_script.py 2>/dev/null || true

cat > /tmp/statsd_application_telemetry_export_script.py << 'PYSCRIPT'
import sqlite3, json, sys

output_file = '/tmp/statsd_application_telemetry_dashboards.json'

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
docker cp /tmp/statsd_application_telemetry_export_script.py graphite:/tmp/statsd_application_telemetry_export_script.py 2>/dev/null
docker exec graphite python3 /tmp/statsd_application_telemetry_export_script.py 2>&1
docker cp graphite:/tmp/statsd_application_telemetry_dashboards.json /tmp/statsd_application_telemetry_dashboards.json 2>/dev/null || true

# Fetch live render API data for payment.success.rate
# We fetch the last 3 minutes of data to see if the daemon was continuously writing
echo "Querying Graphite Render API for live metric data..."
curl -s "http://localhost/render?target=stats.counters.payment.success.rate&format=json&from=-3min" > /tmp/statsd_application_telemetry_data.json || echo "[]" > /tmp/statsd_application_telemetry_data.json

# Package final result JSON
python3 << EOF
import json

task_start = ${TASK_START}

try:
    with open('/tmp/statsd_application_telemetry_dashboards.json') as f:
        dashboards = json.load(f)
except Exception as e:
    dashboards = {"load_error": str(e)}

try:
    with open('/tmp/statsd_application_telemetry_data.json') as f:
        render_data = json.load(f)
except Exception as e:
    render_data = []

result = {
    "task_start": task_start,
    "dashboards": dashboards,
    "render_data": render_data
}

with open('/tmp/statsd_application_telemetry_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/statsd_application_telemetry_result.json")
EOF

echo "=== Export complete ==="