#!/bin/bash
echo "=== Exporting redundant_sensor_drift_calibration result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/redundant_sensor_drift_calibration_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/redundant_sensor_drift_calibration_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/redundant_sensor_drift_calibration_start_ts 2>/dev/null || echo "0")

# Write a Python script to a temp file, then copy into container and execute.
# This avoids heredoc-via-SSH issues since docker exec stdin is not forwarded in all envs.
rm -f /tmp/redundant_sensor_drift_calibration_export_script.py 2>/dev/null || true

cat > /tmp/redundant_sensor_drift_calibration_export_script.py << 'PYSCRIPT'
import sqlite3, json, sys

output_file = '/tmp/redundant_sensor_drift_calibration_dashboards.json'

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

# Ensure correct path in Python script
sed -i "s|/tmp/${task}_dashboards.json|/tmp/redundant_sensor_drift_calibration_dashboards.json|g" /tmp/redundant_sensor_drift_calibration_export_script.py 2>/dev/null || true

# Copy script into container, execute it, copy result out
docker cp /tmp/redundant_sensor_drift_calibration_export_script.py graphite:/tmp/redundant_sensor_drift_calibration_export_script.py 2>/dev/null
docker exec graphite python3 /tmp/redundant_sensor_drift_calibration_export_script.py 2>&1
docker cp graphite:/tmp/redundant_sensor_drift_calibration_dashboards.json /tmp/redundant_sensor_drift_calibration_dashboards.json 2>/dev/null || true

# Package final result
python3 << EOF
import json

task_start = ${TASK_START}

try:
    with open('/tmp/redundant_sensor_drift_calibration_dashboards.json') as f:
        dashboards = json.load(f)
except Exception as e:
    dashboards = {"load_error": str(e)}

result = {
    "task_start": task_start,
    "dashboards": dashboards
}

with open('/tmp/redundant_sensor_drift_calibration_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/redundant_sensor_drift_calibration_result.json")
EOF

echo "=== Export complete ==="