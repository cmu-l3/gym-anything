#!/bin/bash
echo "=== Exporting weekly_ops_comparison result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/weekly_ops_comparison_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/weekly_ops_comparison_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/weekly_ops_comparison_start_ts 2>/dev/null || echo "0")

# Write a Python script to a temp file, then copy into container and execute.
# This avoids heredoc-via-SSH issues (docker exec stdin is not forwarded).
rm -f /tmp/weekly_ops_comparison_export_script.py 2>/dev/null || true

cat > /tmp/weekly_ops_comparison_export_script.py << 'PYSCRIPT'
import sqlite3, json, sys

output_file = '/tmp/weekly_ops_comparison_dashboards.json'

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

# Fix the output filename inside the script (replace placeholder)
sed -i "s|/tmp/${task}_dashboards.json|/tmp/weekly_ops_comparison_dashboards.json|g" /tmp/weekly_ops_comparison_export_script.py 2>/dev/null || true

# Copy script into container, execute it, copy result out
docker cp /tmp/weekly_ops_comparison_export_script.py graphite:/tmp/weekly_ops_comparison_export_script.py 2>/dev/null
docker exec graphite python3 /tmp/weekly_ops_comparison_export_script.py 2>&1
docker cp graphite:/tmp/weekly_ops_comparison_dashboards.json /tmp/weekly_ops_comparison_dashboards.json 2>/dev/null || true

# Package final result (local python3 heredoc works fine)
python3 << EOF
import json

task_start = ${TASK_START}

try:
    with open('/tmp/weekly_ops_comparison_dashboards.json') as f:
        dashboards = json.load(f)
except Exception as e:
    dashboards = {"load_error": str(e)}

result = {
    "task_start": task_start,
    "dashboards": dashboards
}

with open('/tmp/weekly_ops_comparison_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/weekly_ops_comparison_result.json")
EOF

echo "=== Export complete ==="