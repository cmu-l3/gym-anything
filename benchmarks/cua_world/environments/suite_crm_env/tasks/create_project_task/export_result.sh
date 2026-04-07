#!/bin/bash
echo "=== Exporting create_project_task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/create_project_task_final.png

# Get current count
CURRENT_PT_COUNT=$(suitecrm_count "project_task")
echo "$CURRENT_PT_COUNT" > /tmp/current_pt_count.txt

# Query the target project task and output to a TSV file securely
suitecrm_db_query "SELECT pt.id, pt.name, pt.date_start, pt.date_finish, pt.estimated_effort, pt.priority, pt.description, p.name FROM project_task pt LEFT JOIN project p ON pt.project_id = p.id AND p.deleted=0 WHERE pt.name='Pre-migration Site Inspection' AND pt.deleted=0 LIMIT 1" > /tmp/pt_data.tsv

# Python script to safely parse TSV and build the JSON payload
cat > /tmp/export_helper.py << 'PYEOF'
import sys
import json

initial_count = 0
current_count = 0

try:
    with open('/tmp/initial_pt_count.txt', 'r') as f:
        initial_count = int(f.read().strip())
except:
    pass

try:
    with open('/tmp/current_pt_count.txt', 'r') as f:
        current_count = int(f.read().strip())
except:
    pass

result = {
    "pt_found": False,
    "initial_count": initial_count,
    "current_count": current_count,
    "pt_id": "",
    "name": "",
    "date_start": "",
    "date_finish": "",
    "estimated_effort": "",
    "priority": "",
    "description": "",
    "project_name": ""
}

try:
    with open('/tmp/pt_data.tsv', 'r') as f:
        content = f.read().strip()
        if content:
            # -N outputs tab-separated
            parts = content.split('\t')
            if len(parts) >= 8:
                result["pt_found"] = True
                result["pt_id"] = parts[0]
                result["name"] = parts[1]
                result["date_start"] = parts[2]
                result["date_finish"] = parts[3]
                result["estimated_effort"] = parts[4]
                result["priority"] = parts[5]
                # Replace literal escaped newlines with actual newlines if present
                result["description"] = parts[6].replace('\\n', '\n')
                result["project_name"] = parts[7]
except Exception as e:
    result["error"] = str(e)

with open('/tmp/create_project_task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

python3 /tmp/export_helper.py

chmod 666 /tmp/create_project_task_result.json 2>/dev/null || true

echo "Result saved to /tmp/create_project_task_result.json"
cat /tmp/create_project_task_result.json
echo "=== create_project_task export complete ==="