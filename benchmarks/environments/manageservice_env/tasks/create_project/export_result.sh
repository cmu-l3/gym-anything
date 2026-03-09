#!/bin/bash
set -e
echo "=== Exporting create_project task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather timing data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_project_count.txt 2>/dev/null || echo "0")
PROJECT_TABLE=$(cat /tmp/project_table_name.txt 2>/dev/null || echo "projecttab")

# 3. Query Database for the Created Project
# We look for the specific title or a recently created project
echo "Searching database for project..."

# Attempt 1: Search by specific title keywords
# Using lower case for case-insensitive matching
PROJECT_DATA=$(sdp_db_exec "SELECT projectid, title, description, priority, scheduledstartdate, scheduledenddate FROM $PROJECT_TABLE WHERE LOWER(title) LIKE '%email migration%' AND LOWER(title) LIKE '%microsoft 365%' ORDER BY projectid DESC LIMIT 1;" 2>/dev/null || echo "")

# Attempt 2: If not found, check the most recent project if count increased
if [ -z "$PROJECT_DATA" ]; then
    CURRENT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM $PROJECT_TABLE;" 2>/dev/null || echo "0")
    if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
        # Get the latest project
        PROJECT_DATA=$(sdp_db_exec "SELECT projectid, title, description, priority, scheduledstartdate, scheduledenddate FROM $PROJECT_TABLE ORDER BY projectid DESC LIMIT 1;" 2>/dev/null || echo "")
    fi
fi

# 4. Parse DB Result
PROJECT_FOUND="false"
P_ID=""
P_TITLE=""
P_DESC=""
P_PRIORITY=""
P_START=""
P_END=""

if [ -n "$PROJECT_DATA" ]; then
    PROJECT_FOUND="true"
    # Postgres output format depends on sdp_db_exec, assuming pipe separated based on task_utils
    # But usually psql -A -t uses pipe by default or we can force it.
    # Let's ensure we parse correctly. sdp_db_exec uses -A -t (unaligned, tuples only), separator is usually pipe
    
    P_ID=$(echo "$PROJECT_DATA" | cut -d'|' -f1)
    P_TITLE=$(echo "$PROJECT_DATA" | cut -d'|' -f2)
    P_DESC=$(echo "$PROJECT_DATA" | cut -d'|' -f3)
    P_PRIORITY=$(echo "$PROJECT_DATA" | cut -d'|' -f4)
    P_START=$(echo "$PROJECT_DATA" | cut -d'|' -f5)
    P_END=$(echo "$PROJECT_DATA" | cut -d'|' -f6)
fi

# 5. Check if Priority is ID or String
# Sometimes priority is stored as an ID. If so, try to resolve it (simplified mapping)
# Assuming 3/High or 4/High.
if [[ "$P_PRIORITY" =~ ^[0-9]+$ ]]; then
    # It's an ID, leave it for python to judge or try to fetch name
    PRIORITY_NAME=$(sdp_db_exec "SELECT name FROM prioritydefinition WHERE priorityid=$P_PRIORITY" 2>/dev/null || echo "$P_PRIORITY")
    P_PRIORITY="$PRIORITY_NAME"
fi

# 6. Check for VLM evidence (screenshots)
# Framework captures trajectory, but we check if we have our own
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 7. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_found": $PROJECT_FOUND,
    "project_data": {
        "id": "$P_ID",
        "title": $(echo "$P_TITLE" | jq -R .),
        "description": $(echo "$P_DESC" | jq -R .),
        "priority": "$P_PRIORITY",
        "start_date": "$P_START",
        "end_date": "$P_END"
    },
    "initial_count": $INITIAL_COUNT,
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# 8. Save to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="