#!/bin/bash
echo "=== Exporting Exit Interview Workflow Configuration Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
sleep 1

# Check if Firefox is running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use Python to safely extract DB data to JSON format
cat > /tmp/export_db_to_json.py << 'EOF'
import subprocess
import json
import time
import os

def query(sql):
    cmd = ['docker', 'exec', 'sentrifugo-db', 'mysql', '-u', 'root', '-prootpass123', 'sentrifugo', '-N', '-B', '-e', sql]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            return []
        return [line.split('\t') for line in res.stdout.strip().split('\n') if line]
    except Exception as e:
        return []

# Find tables dynamically in case of schema variations
tables = [r[0] for r in query("SHOW TABLES;")]
cat_table = next((t for t in tables if 'exit' in t and 'categor' in t), 'main_exitcategories')
q_table = next((t for t in tables if 'exit' in t and 'question' in t), 'main_exitquestions')
dept_table = next((t for t in tables if 'exit' in t and 'clearance' in t and 'dept' in t), 'main_exitclearancedepts')

result = {
    "clearance_depts": [],
    "categories": [],
    "questions": [],
    "legacy_questions_found": []
}

# Export Clearance Departments (active only)
dept_rows = query(f"SELECT deptname FROM {dept_table} WHERE isactive=1;")
result["clearance_depts"] = [r[0].strip() for r in dept_rows if r]

# Export Categories (active only)
cat_rows = query(f"SELECT id, categoryname FROM {cat_table} WHERE isactive=1;")
cat_map = {}
for r in cat_rows:
    if len(r) >= 2:
        cat_map[r[0]] = r[1].strip()
        result["categories"].append(r[1].strip())

# Export Questions and their mapped categories (active only)
q_rows = query(f"SELECT question, category_id FROM {q_table} WHERE isactive=1;")
legacy_targets = ['How would you rate your manager?', 'Why are you leaving?', 'Would you recommend us?']

for r in q_rows:
    if len(r) >= 2:
        q_text = r[0].strip()
        c_id = r[1]
        c_name = cat_map.get(c_id, "UNKNOWN")
        
        if any(leg in q_text for leg in legacy_targets):
            result["legacy_questions_found"].append(q_text)
        else:
            result["questions"].append({
                "text": q_text,
                "category": c_name
            })

# Save JSON result
with open('/tmp/task_result_payload.json', 'w') as f:
    json.dump(result, f, indent=4)
EOF

python3 /tmp/export_db_to_json.py

# Read payload and inject framework fields
PAYLOAD=$(cat /tmp/task_result_payload.json 2>/dev/null || echo '{"error": "Failed to read DB state"}')

TEMP_JSON=$(mktemp /tmp/exit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_end.png",
    "db_state": $PAYLOAD
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="