#!/bin/bash
set -e
echo "=== Exporting asset_maintenance_logging results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Write a Python script to robustly pull maintenance records and output JSON
cat > /tmp/export_db.py << 'EOF'
import subprocess
import json

def query_db(query):
    # Query database safely via docker exec
    cmd = ["docker", "exec", "snipeit-db", "mysql", "-u", "snipeit", "-psnipeit_pass", "snipeit", "-N", "-e", query]
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
        return res
    except Exception:
        return ""

def get_record(tag, keyword):
    query = f"""
        SELECT am.asset_maintenance_type, am.title, am.start_date, am.completion_date,
               am.cost, s.name, am.notes
        FROM asset_maintenances am
        JOIN assets a ON am.asset_id = a.id
        LEFT JOIN suppliers s ON am.supplier_id = s.id
        WHERE a.asset_tag = '{tag}'
        AND am.title LIKE '%{keyword}%'
        ORDER BY am.id DESC LIMIT 1
    """
    data = query_db(query)
    if not data:
        return {"tag": tag, "found": False}
    parts = data.split('\t')
    if len(parts) < 7:
        parts += [""] * (7 - len(parts))
    return {
        "tag": tag,
        "found": True,
        "type": parts[0],
        "title": parts[1],
        "start_date": parts[2],
        "completion_date": parts[3],
        "cost": parts[4],
        "supplier": parts[5],
        "notes": parts[6]
    }

try:
    with open('/tmp/initial_maintenance_count.txt', 'r') as f:
        initial_count = int(f.read().strip() or 0)
except Exception:
    initial_count = 0

try:
    final_count = int(query_db("SELECT COUNT(*) FROM asset_maintenances") or 0)
except Exception:
    final_count = 0

result = {
    "initial_count": initial_count,
    "final_count": final_count,
    "records": {
        "asset_0001": get_record("ASSET-0001", "preventive maintenance"),
        "asset_0002": get_record("ASSET-0002", "critical failure"),
        "asset_0003": get_record("ASSET-0003", "radiology workstation"),
        "asset_0005": get_record("ASSET-0005", "quarterly maintenance")
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

# Run python export script
python3 /tmp/export_db.py

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="