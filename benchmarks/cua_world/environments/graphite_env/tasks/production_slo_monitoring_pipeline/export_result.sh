#!/bin/bash
echo "=== Exporting production_slo_monitoring_pipeline result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/production_slo_monitoring_pipeline_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/production_slo_monitoring_pipeline_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/production_slo_monitoring_pipeline_start_ts 2>/dev/null || echo "0")

# 1. Export dashboards from SQLite
rm -f /tmp/production_slo_monitoring_pipeline_export_script.py 2>/dev/null || true

cat > /tmp/production_slo_monitoring_pipeline_export_script.py << 'PYSCRIPT'
import sqlite3, json, sys

output_file = '/tmp/production_slo_monitoring_pipeline_dashboards.json'

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

docker cp /tmp/production_slo_monitoring_pipeline_export_script.py graphite:/tmp/production_slo_monitoring_pipeline_export_script.py 2>/dev/null
docker exec graphite python3 /tmp/production_slo_monitoring_pipeline_export_script.py 2>&1
docker cp graphite:/tmp/production_slo_monitoring_pipeline_dashboards.json /tmp/production_slo_monitoring_pipeline_dashboards.json 2>/dev/null || true

# 2. Query Render API for custom metrics (verify data was fed)
curl -s "http://localhost/render?target=apps.payment.*&from=-4d&format=json" \
    -o /tmp/production_slo_monitoring_pipeline_metrics.json 2>/dev/null || \
    echo "[]" > /tmp/production_slo_monitoring_pipeline_metrics.json

# 3. Package final result
python3 << EOF
import json

task_start = ${TASK_START}

try:
    with open('/tmp/production_slo_monitoring_pipeline_dashboards.json') as f:
        dashboards = json.load(f)
except Exception as e:
    dashboards = {"load_error": str(e)}

try:
    with open('/tmp/production_slo_monitoring_pipeline_metrics.json') as f:
        metrics_data = json.load(f)
except Exception as e:
    metrics_data = []

result = {
    "task_start": task_start,
    "dashboards": dashboards,
    "metrics_data": metrics_data
}

with open('/tmp/production_slo_monitoring_pipeline_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/production_slo_monitoring_pipeline_result.json")
EOF

echo "=== Export complete ==="
