#!/bin/bash
echo "=== Exporting Viral Churn Risk Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Output File
OUTPUT_FILE="/home/ga/at_risk_users.json"
FILE_EXISTS="false"
FILE_CONTENT="[]"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Read content, keeping it safe for JSON embedding
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | tr -d '\n' | sed 's/"/\\"/g')
fi

# 2. Query Database State (Run Python script inside container to query localhost)
cat > /tmp/query_db_state.py << 'EOF'
import sys
import json
import base64
import urllib.request

BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}

def sql(command):
    req = urllib.request.Request(
        f"{BASE_URL}/command/demodb/sql",
        data=json.dumps({"command": command}).encode(),
        headers=HEADERS,
        method="POST"
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.load(resp)
    except Exception as e:
        return {"error": str(e)}

def get_schema():
    req = urllib.request.Request(
        f"{BASE_URL}/database/demodb",
        headers={"Authorization": f"Basic {AUTH}"},
        method="GET"
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.load(resp)
    except Exception:
        return {}

results = {}

# Check 1: Schema - FiledTicket edge
schema = get_schema()
classes = {c['name']: c for c in schema.get('classes', [])}
results['filed_ticket_class_exists'] = 'FiledTicket' in classes
if 'FiledTicket' in classes:
    results['filed_ticket_extends_e'] = 'E' in classes['FiledTicket'].get('superClass', '') or 'E' in classes['FiledTicket'].get('superClasses', [])
else:
    results['filed_ticket_extends_e'] = False

# Check 2: Schema - ChurnRisk property
profiles_cls = classes.get('Profiles', {})
props = {p['name']: p for p in profiles_cls.get('properties', [])}
results['churn_risk_property_exists'] = 'ChurnRisk' in props
results['churn_risk_type'] = props.get('ChurnRisk', {}).get('type', 'UNKNOWN')

# Check 3: Linkage (Profiles -> Tickets)
# Verify John (High) is linked
link_res = sql("SELECT count(*) as cnt FROM FiledTicket WHERE out.Email = 'john.smith@example.com' AND in.email = 'john.smith@example.com'")
results['john_linked_count'] = link_res.get('result', [{}])[0].get('cnt', 0)

# Check 4: Risk Tagging
# Maria should be marked (Friend of John)
maria_res = sql("SELECT ChurnRisk FROM Profiles WHERE Email = 'maria.garcia@example.com'")
results['maria_risk_val'] = maria_res.get('result', [{}])[0].get('ChurnRisk', None)

# Sophie should NOT be marked (Friend of David - Low)
sophie_res = sql("SELECT ChurnRisk FROM Profiles WHERE Email = 'sophie.martin@example.com'")
results['sophie_risk_val'] = sophie_res.get('result', [{}])[0].get('ChurnRisk', None)

print(json.dumps(results))
EOF

# Execute query script
DB_STATE=$(python3 /tmp/query_db_state.py)

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Assemble Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file_exists": $FILE_EXISTS,
    "output_file_content_raw": "$FILE_CONTENT",
    "db_state": $DB_STATE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="