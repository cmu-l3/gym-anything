#!/bin/bash
echo "=== Exporting flapping_alert_noise_reduction result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/flapping_alert_noise_reduction_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/flapping_alert_noise_reduction_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/flapping_alert_noise_reduction_start_ts 2>/dev/null || echo "0")

# Write a Python script to a temp file, then copy into container and execute.
# This extracts the saved dashboards from Graphite's internal SQLite DB.
rm -f /tmp/flapping_alert_noise_reduction_export_script.py 2>/dev/null || true

cat > /tmp/flapping_alert_noise_reduction_export_script.py << 'PYSCRIPT'
import sqlite3, json, sys

output_file = '/tmp/flapping_alert_noise_reduction_dashboards.json'

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

# Fix the output filename inside the script just in case
sed -i "s|/tmp/${task}_dashboards.json|/tmp/flapping_alert_noise_reduction_dashboards.json|g" /tmp/flapping_alert_noise_reduction_export_script.py 2>/dev/null || true

# Copy script into container, execute it, copy result out
docker cp /tmp/flapping_alert_noise_reduction_export_script.py graphite:/tmp/flapping_alert_noise_reduction_export_script.py 2>/dev/null
docker exec graphite python3 /tmp/flapping_alert_noise_reduction_export_script.py 2>&1
docker cp graphite:/tmp/flapping_alert_noise_reduction_dashboards.json /tmp/flapping_alert_noise_reduction_dashboards.json 2>/dev/null || true

# Package final result
python3 << EOF
import json

task_start = ${TASK_START}

try:
    with open('/tmp/flapping_alert_noise_reduction_dashboards.json') as f:
        dashboards = json.load(f)
except Exception as e:
    dashboards = {"load_error": str(e)}

result = {
    "task_start": task_start,
    "dashboards": dashboards
}

with open('/tmp/flapping_alert_noise_reduction_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/flapping_alert_noise_reduction_result.json")
EOF

echo "=== Export complete ==="