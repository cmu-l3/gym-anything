#!/bin/bash
echo "=== Exporting Session Cleanup Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare Python script to extract complex state to JSON
# We use this because parsing JSON in bash is fragile, and we need to check
# schema, data, functions, and schedule all at once.

cat > /tmp/extract_state.py << 'EOF'
import sys
import json
import urllib.request
import base64
import time

ROOT_PASS = "GymAnything123!"
BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(f"root:{ROOT_PASS}".encode()).decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Content-Type": "application/json"
}

def sql(command):
    try:
        req = urllib.request.Request(
            f"{BASE_URL}/command/demodb/sql",
            data=json.dumps({"command": command}).encode(),
            headers=HEADERS,
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except Exception as e:
        return {"error": str(e)}

def get_schema():
    try:
        req = urllib.request.Request(f"{BASE_URL}/database/demodb", headers=HEADERS)
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except Exception as e:
        return {"error": str(e)}

result = {}

# 1. Check Schema (UserSessions class)
db_info = get_schema()
classes = db_info.get("classes", [])
user_sessions_cls = next((c for c in classes if c["name"] == "UserSessions"), None)

if user_sessions_cls:
    result["class_exists"] = True
    result["properties"] = [p["name"] for p in user_sessions_cls.get("properties", [])]
else:
    result["class_exists"] = False
    result["properties"] = []

# 2. Check Function (cleanup_sessions)
func_res = sql("SELECT name, code, language FROM OFunction WHERE name = 'cleanup_sessions'")
funcs = func_res.get("result", [])
if funcs:
    result["function_exists"] = True
    result["function_code"] = funcs[0].get("code", "")
    result["function_lang"] = funcs[0].get("language", "")
else:
    result["function_exists"] = False

# 3. Check Schedule
# In OrientDB, OSchedule entries link to the function.
sched_res = sql("SELECT function.name as fname, rule FROM OSchedule WHERE function.name = 'cleanup_sessions'")
schedules = sched_res.get("result", [])
if schedules:
    result["schedule_exists"] = True
    result["schedule_rule"] = schedules[0].get("rule", "")
else:
    result["schedule_exists"] = False

# 4. Check Data Content
# Total count
count_res = sql("SELECT count(*) as cnt FROM UserSessions")
total_count = count_res.get("result", [{}])[0].get("cnt", 0)
result["total_records"] = total_count

# Check for expired records (Created < 24 hours ago)
# We assume 'now' is sysdate(). 24h = 86400000 ms
expired_res = sql("SELECT count(*) as cnt FROM UserSessions WHERE Created < sysdate() - 86400000")
expired_count = expired_res.get("result", [{}])[0].get("cnt", 0)
result["expired_records_remaining"] = expired_count

# Check for active records (Created > 24 hours ago)
active_res = sql("SELECT count(*) as cnt FROM UserSessions WHERE Created > sysdate() - 86400000")
active_count = active_res.get("result", [{}])[0].get("cnt", 0)
result["active_records_remaining"] = active_count

# Check if emails look valid (sampling one)
sample_res = sql("SELECT UserEmail FROM UserSessions LIMIT 1")
if sample_res.get("result"):
    result["sample_email"] = sample_res["result"][0].get("UserEmail", "")

print(json.dumps(result, indent=2))
EOF

# Execute the python script and save result
python3 /tmp/extract_state.py > /tmp/task_result.json

# Check if app is running (OrientDB is a service, but check Firefox too)
FIREFOX_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Add system info to json using jq
jq --arg firefox "$FIREFOX_RUNNING" '. + {"firefox_running": ($firefox == "true")}' /tmp/task_result.json > /tmp/task_result_final.json
mv /tmp/task_result_final.json /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json