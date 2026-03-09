#!/bin/bash
set -e

echo "=== Exporting Nested IVR Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data from Database using Python for clean JSON formatting
# We execute the python script inside the VM, which queries the DB via docker exec

cat > /tmp/extract_ivr_data.py << 'EOF'
import json
import subprocess
import sys

def run_query(query):
    cmd = [
        "docker", "exec", "vicidial", "mysql", 
        "-ucron", "-p1234", "-D", "asterisk", 
        "-N", "-B", "-e", query
    ]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8')
        rows = []
        for line in result.strip().split('\n'):
            if line:
                rows.append(line.split('\t'))
        return rows
    except Exception as e:
        return []

data = {
    "ingroups": {},
    "menus": {},
    "options": []
}

# Fetch In-Groups
groups = run_query("SELECT group_id, group_name, active FROM vicidial_inbound_groups WHERE group_id IN ('TC_SALES', 'TC_TECH')")
for g in groups:
    if len(g) >= 3:
        data["ingroups"][g[0]] = {"name": g[1], "active": g[2]}

# Fetch Menus
menus = run_query("SELECT menu_id, menu_name, menu_prompt FROM vicidial_call_menu WHERE menu_id IN ('MENU_MAIN', 'MENU_SUB_SUP')")
for m in menus:
    if len(m) >= 3:
        data["menus"][m[0]] = {"name": m[1], "prompt": m[2]}

# Fetch Options
opts = run_query("SELECT menu_id, `option`, route, route_value, route_value_context FROM vicidial_call_menu_options WHERE menu_id IN ('MENU_MAIN', 'MENU_SUB_SUP')")
for o in opts:
    if len(o) >= 4:
        data["options"].append({
            "menu_id": o[0],
            "option": o[1],
            "route": o[2],
            "value": o[3],
            "context": o[4] if len(o) > 4 else ""
        })

print(json.dumps(data, indent=2))
EOF

# Execute extraction
python3 /tmp/extract_ivr_data.py > /tmp/task_result.json

# Add basic metadata to result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
jq --arg start "$TASK_START" '. + {"task_start": $start}' /tmp/task_result.json > /tmp/task_result.final.json
mv /tmp/task_result.final.json /tmp/task_result.json

echo "Exported Data:"
cat /tmp/task_result.json
echo "=== Export Complete ==="