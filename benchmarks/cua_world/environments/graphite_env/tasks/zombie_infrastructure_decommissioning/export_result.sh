#!/bin/bash
echo "=== Exporting zombie_infrastructure_decommissioning result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/zombie_infrastructure_decommissioning_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/zombie_infrastructure_decommissioning_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/zombie_infrastructure_decommissioning_start_ts 2>/dev/null || echo "0")

# Write a Python script to a temp file, then copy into container and execute.
# This avoids heredoc-via-SSH issues (docker exec stdin is not forwarded).
rm -f /tmp/zombie_infrastructure_decommissioning_export_script.py 2>/dev/null || true

cat > /tmp/zombie_infrastructure_decommissioning_export_script.py << 'PYSCRIPT'
import sqlite3, json, sys, os

output_file = '/tmp/zombie_infrastructure_decommissioning_dashboards.json'
db_path = '/opt/graphite/storage/graphite.db'

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Get DB modification time for anti-gaming
    db_mtime = int(os.path.getmtime(db_path)) if os.path.exists(db_path) else 0

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
    
    result_data = {
        "db_mtime": db_mtime,
        "dashboards": dashboards
    }
    
    with open(output_file, 'w') as f:
        json.dump(result_data, f)
        
    print("Dashboard data written: " + str(len(dashboards)) + " dashboards")
except Exception as e:
    sys.stderr.write("ERROR: " + str(e) + "\n")
    with open(output_file, 'w') as f:
        json.dump({"error": str(e)}, f)
PYSCRIPT

# Fix the output filename inside the script (replace placeholder)
sed -i "s|/tmp/${task}_dashboards.json|/tmp/zombie_infrastructure_decommissioning_dashboards.json|g" /tmp/zombie_infrastructure_decommissioning_export_script.py 2>/dev/null || true

# Copy script into container, execute it, copy result out
docker cp /tmp/zombie_infrastructure_decommissioning_export_script.py graphite:/tmp/zombie_infrastructure_decommissioning_export_script.py 2>/dev/null
docker exec graphite python3 /tmp/zombie_infrastructure_decommissioning_export_script.py 2>&1
docker cp graphite:/tmp/zombie_infrastructure_decommissioning_dashboards.json /tmp/zombie_infrastructure_decommissioning_dashboards.json 2>/dev/null || true

# Package final result
python3 << EOF
import json
import os

task_start = int(${TASK_START})

try:
    with open('/tmp/zombie_infrastructure_decommissioning_dashboards.json') as f:
        container_data = json.load(f)
        dashboards = container_data.get("dashboards", {})
        db_mtime = container_data.get("db_mtime", 0)
except Exception as e:
    dashboards = {"load_error": str(e)}
    db_mtime = 0

result = {
    "task_start": task_start,
    "db_mtime": db_mtime,
    "dashboards": dashboards
}

with open('/tmp/zombie_infrastructure_decommissioning_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/zombie_infrastructure_decommissioning_result.json")
EOF

echo "=== Export complete ==="