#!/bin/bash
echo "=== Exporting Customer Value Segmentation Result ==="

# Ensure safe PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/platinum_customers.json"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Analyze Agent's Output File
OUTPUT_EXISTS="false"
OUTPUT_VALID="false"
OUTPUT_CONTENT="[]"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    # Try to parse JSON
    if jq -e . "$OUTPUT_FILE" >/dev/null 2>&1; then
        OUTPUT_VALID="true"
        # Read content for verifier (limit size)
        OUTPUT_CONTENT=$(cat "$OUTPUT_FILE")
    fi
fi

# 3. Query OrientDB for Internal State Verification
# We need to know:
# A. Does Profiles have 'CustomerTier' property?
# B. Do the tracer accounts have the correct CustomerTier values?

echo "Querying OrientDB state..."

cat << EOF > /tmp/check_db_state.py
import urllib.request
import json
import base64
import sys

BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}

def get_class(classname):
    try:
        req = urllib.request.Request(f"{BASE_URL}/database/demodb", headers=HEADERS)
        with urllib.request.urlopen(req) as r:
            data = json.loads(r.read())
            for cls in data.get('classes', []):
                if cls['name'] == classname:
                    return cls
    except Exception:
        pass
    return None

def sql_query(query):
    try:
        # URL encode the query for GET
        safe_query = urllib.parse.quote(query)
        req = urllib.request.Request(f"{BASE_URL}/query/demodb/sql/{safe_query}/100", headers=HEADERS)
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read()).get('result', [])
    except Exception as e:
        return []

state = {
    "property_exists": False,
    "property_type": None,
    "tracers": {}
}

# Check Schema
profiles_cls = get_class("Profiles")
if profiles_cls:
    for prop in profiles_cls.get("properties", []):
        if prop["name"] == "CustomerTier":
            state["property_exists"] = True
            state["property_type"] = prop.get("type")

# Check Tracer Data
tracer_emails = [
    "vip_tracer@example.com", 
    "mid_tracer@example.com", 
    "low_tracer@example.com", 
    "inactive_tracer@example.com"
]

for email in tracer_emails:
    res = sql_query(f"SELECT CustomerTier FROM Profiles WHERE Email='{email}'")
    if res:
        state["tracers"][email] = res[0].get("CustomerTier")
    else:
        state["tracers"][email] = "__NOT_FOUND__"

print(json.dumps(state))
EOF

DB_STATE_JSON=$(python3 /tmp/check_db_state.py 2>/dev/null || echo "{}")

# 4. Construct Final Result JSON
# We embed the db state and the agent output into one JSON for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
    --argjson db_state "$DB_STATE_JSON" \
    --arg output_exists "$OUTPUT_EXISTS" \
    --arg output_valid "$OUTPUT_VALID" \
    --argjson output_content "$OUTPUT_CONTENT" \
    --arg task_start "$TASK_START" \
    --arg task_end "$TASK_END" \
    '{
        db_state: $db_state,
        agent_output: {
            exists: ($output_exists == "true"),
            valid_json: ($output_valid == "true"),
            content: $output_content
        },
        timestamps: {
            start: $task_start,
            end: $task_end
        }
    }' > "$TEMP_JSON"

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"