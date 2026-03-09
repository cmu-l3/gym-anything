#!/bin/bash
echo "=== Exporting class_hierarchy_refactor results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Report File
REPORT_PATH="/home/ga/hotel_hierarchy_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
fi

# 3. Inspect Database State via Python Script
# We need to check schema (classes, inheritance, properties) and data counts
echo "Inspecting database state..."

cat > /tmp/inspect_db.py << 'PYEOF'
import sys, json, urllib.request, base64

BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}

def sql_cmd(command):
    try:
        req = urllib.request.Request(
            f"{BASE_URL}/command/demodb/sql",
            data=json.dumps({"command": command}).encode(),
            headers=HEADERS,
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=5) as r:
            return json.loads(r.read()).get("result", [])
    except Exception as e:
        return []

def get_schema():
    try:
        req = urllib.request.Request(f"{BASE_URL}/database/demodb", headers=HEADERS, method="GET")
        with urllib.request.urlopen(req, timeout=5) as r:
            return json.loads(r.read())
    except Exception:
        return {}

def get_count(query):
    res = sql_cmd(query)
    return res[0].get('cnt', 0) if res else 0

schema = get_schema()
classes_info = {c['name']: c for c in schema.get('classes', [])}

def check_class(name):
    if name not in classes_info: return None
    c = classes_info[name]
    return {
        "exists": True,
        "superClass": c.get("superClass", ""),
        "properties": [p["name"] for p in c.get("properties", [])]
    }

# Gather metrics
db_state = {
    "classes": {
        "BudgetHotels": check_class("BudgetHotels"),
        "MidRangeHotels": check_class("MidRangeHotels"),
        "LuxuryHotels": check_class("LuxuryHotels"),
        "Hotels": check_class("Hotels")
    },
    "counts": {
        "Hotels_Total_Polymorphic": get_count("SELECT COUNT(*) as cnt FROM Hotels"),
        "Hotels_Direct": get_count("SELECT COUNT(*) as cnt FROM Hotels WHERE @class='Hotels'"),
        "Budget_Direct": get_count("SELECT COUNT(*) as cnt FROM BudgetHotels"),
        "MidRange_Direct": get_count("SELECT COUNT(*) as cnt FROM MidRangeHotels"),
        "Luxury_Direct": get_count("SELECT COUNT(*) as cnt FROM LuxuryHotels")
    },
    "property_checks": {
        "Budget_Wifi_Set": get_count("SELECT COUNT(*) as cnt FROM BudgetHotels WHERE HasFreeWifi = true"),
        "MidRange_Pool_Set": get_count("SELECT COUNT(*) as cnt FROM MidRangeHotels WHERE HasPool = true"),
        "Luxury_Spa_Set": get_count("SELECT COUNT(*) as cnt FROM LuxuryHotels WHERE HasSpa = true"),
        "Tier_Budget_Set": get_count("SELECT COUNT(*) as cnt FROM Hotels WHERE Tier = 'Budget'"),
        "Tier_MidRange_Set": get_count("SELECT COUNT(*) as cnt FROM Hotels WHERE Tier = 'MidRange'"),
        "Tier_Luxury_Set": get_count("SELECT COUNT(*) as cnt FROM Hotels WHERE Tier = 'Luxury'")
    }
}

print(json.dumps(db_state))
PYEOF

DB_STATE_JSON=$(python3 /tmp/inspect_db.py)

# 4. Load Expected Counts
EXPECTED_JSON="{}"
if [ -f "/tmp/expected_counts.json" ]; then
    EXPECTED_JSON=$(cat /tmp/expected_counts.json)
fi

# 5. Compile Full Result
cat > /tmp/result_data.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_file": {
        "exists": $REPORT_EXISTS,
        "mtime": $REPORT_MTIME,
        "content_b64": "$REPORT_CONTENT"
    },
    "db_state": $DB_STATE_JSON,
    "expected_counts": $EXPECTED_JSON
}
EOF

# Move to final location
cp /tmp/result_data.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"