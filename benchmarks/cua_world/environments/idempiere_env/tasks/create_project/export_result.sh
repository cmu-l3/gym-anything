#!/bin/bash
echo "=== Exporting create_project results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Basic info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_project_count.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then CLIENT_ID=11; fi

# 3. Query the Project Header
echo "--- Querying Project Header ---"
# We define a custom separator |~| to safely parse the output
PROJECT_DATA=$(idempiere_query "SELECT c_project_id, name, description, plannedamt, datecontract, datefinish, created FROM c_project WHERE value='WH-RENO-2024' AND ad_client_id=$CLIENT_ID")

PROJECT_FOUND="false"
PROJECT_ID=""
PROJECT_NAME=""
PROJECT_DESC=""
PROJECT_AMT="0"
PROJECT_DATE_CONTRACT=""
PROJECT_DATE_FINISH=""
PROJECT_CREATED=""

if [ -n "$PROJECT_DATA" ]; then
    PROJECT_FOUND="true"
    # Parse the pipe-separated data from psql -A -t (default from task_utils helper)
    # Format from helper is usually value|value|value
    PROJECT_ID=$(echo "$PROJECT_DATA" | cut -d'|' -f1)
    PROJECT_NAME=$(echo "$PROJECT_DATA" | cut -d'|' -f2)
    PROJECT_DESC=$(echo "$PROJECT_DATA" | cut -d'|' -f3)
    PROJECT_AMT=$(echo "$PROJECT_DATA" | cut -d'|' -f4)
    PROJECT_DATE_CONTRACT=$(echo "$PROJECT_DATA" | cut -d'|' -f5)
    PROJECT_DATE_FINISH=$(echo "$PROJECT_DATA" | cut -d'|' -f6)
    PROJECT_CREATED=$(echo "$PROJECT_DATA" | cut -d'|' -f7)
fi

# 4. Query the Project Phases (if project exists)
PHASES_JSON="[]"
if [ "$PROJECT_FOUND" = "true" ]; then
    echo "--- Querying Project Phases ---"
    # We construct a JSON array directly using a loop or python, but simpler to dump text and parse in Python verifier
    # Let's dump raw lines of phase data
    PHASE_DATA=$(idempiere_query "SELECT seqno, name, plannedamt, startdate, enddate FROM c_projectphase WHERE c_project_id=$PROJECT_ID ORDER BY seqno ASC")
    
    # Convert raw pipe-delimited phase data to a JSON array string
    # Input format per line: 10|Name|25000|2024-07-01|...
    PHASES_JSON=$(echo "$PHASE_DATA" | python3 -c '
import sys, json
phases = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    parts = line.split("|")
    if len(parts) >= 5:
        phases.append({
            "seq": parts[0],
            "name": parts[1],
            "amt": parts[2],
            "start": parts[3],
            "end": parts[4]
        })
print(json.dumps(phases))
')
fi

# 5. Create Result JSON
# Handle timestamp conversion for "created during task" check in verifier
# (Postgres timestamp format needs parsing, we pass it raw)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START,
    "initial_project_count": $INITIAL_COUNT,
    "project_found": $PROJECT_FOUND,
    "project": {
        "id": "$PROJECT_ID",
        "name": "$(echo $PROJECT_NAME | sed 's/"/\\"/g')",
        "description": "$(echo $PROJECT_DESC | sed 's/"/\\"/g')",
        "planned_amt": "$PROJECT_AMT",
        "date_contract": "$PROJECT_DATE_CONTRACT",
        "date_finish": "$PROJECT_DATE_FINISH",
        "created_ts": "$PROJECT_CREATED"
    },
    "phases": $PHASES_JSON
}
EOF

# 6. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="