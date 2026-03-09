#!/bin/bash
# Export script for Program Rule Data Quality task

echo "=== Exporting Program Rule Data Quality Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")
CHILD_PROG_ID=$(cat /tmp/child_program_id.txt 2>/dev/null || echo "")

echo "Checking for new Program Rule Variables..."
# Fetch variables created after start time
# Note: DHIS2 API filtering by 'created' might be tricky with exact timestamps, so we fetch recent and filter in python
VARIABLES_JSON=$(dhis2_api "programRuleVariables?filter=program.id:eq:$CHILD_PROG_ID&fields=id,name,created,dataElement[id,name],trackedEntityAttribute[id,name],programRuleVariableSourceType&order=created:desc&pageSize=20" 2>/dev/null)

NEW_VARIABLES=$(echo "$VARIABLES_JSON" | python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    # Normalize ISO format for robust comparison
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('Z', '+00:00'))
    except:
        task_start = datetime(2025, 1, 1) # Fallback

    new_items = []
    for item in data.get('programRuleVariables', []):
        created_str = item.get('created', '')
        try:
            # DHIS2 often returns milliseconds, Python <3.11 ISO parser can be picky
            created_str = created_str.replace('Z', '+00:00')
            created = datetime.fromisoformat(created_str)
            if created >= task_start:
                new_items.append(item)
        except Exception as e:
            pass # Skip invalid dates
            
    print(json.dumps(new_items))
except:
    print('[]')
" 2>/dev/null)

echo "Checking for new Program Rules..."
# Fetch rules created after start time
# Need nested fields to verify actions
RULES_JSON=$(dhis2_api "programRules?filter=program.id:eq:$CHILD_PROG_ID&fields=id,name,created,condition,programRuleActions[id,programRuleActionType,content]&order=created:desc&pageSize=20" 2>/dev/null)

NEW_RULES=$(echo "$RULES_JSON" | python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('Z', '+00:00'))
    except:
        task_start = datetime(2025, 1, 1)

    new_items = []
    for item in data.get('programRules', []):
        created_str = item.get('created', '')
        try:
            created_str = created_str.replace('Z', '+00:00')
            created = datetime.fromisoformat(created_str)
            if created >= task_start:
                new_items.append(item)
        except:
            pass
            
    print(json.dumps(new_items))
except:
    print('[]')
" 2>/dev/null)

# Verify app state (Maintenance app open?)
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# Construct result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_iso": "$TASK_START_ISO",
    "program_id": "$CHILD_PROG_ID",
    "new_variables": $NEW_VARIABLES,
    "new_rules": $NEW_RULES,
    "final_window_title": "$WINDOW_TITLE",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="