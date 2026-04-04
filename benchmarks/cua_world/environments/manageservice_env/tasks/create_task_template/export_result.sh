#!/bin/bash
echo "=== Exporting Task Template Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ==============================================================================
# Extract Data from Database
# ==============================================================================

# We need to join tables to get meaningful data:
# tasktemplate: holds title, priorityid
# taskdetails: holds description (sometimes linked by tasktemplateid)
# prioritydefinition: holds priorityname (High/Medium/Low)

# Query for the specific template created by the agent
# Note: output format is simple pipe-separated values for easier parsing
DB_RESULT=$(sdp_db_exec "
SELECT 
    tt.title, 
    COALESCE(td.description, ''), 
    COALESCE(pd.priorityname, 'Normal'),
    tt.createdtime 
FROM tasktemplate tt 
LEFT JOIN taskdetails td ON tt.tasktemplateid = td.tasktemplateid 
LEFT JOIN prioritydefinition pd ON tt.priorityid = pd.priorityid 
WHERE tt.title ILIKE '%Server Patching Protocol%';
")

# If DB_RESULT is empty, the record wasn't found
if [ -z "$DB_RESULT" ]; then
    TEMPLATE_FOUND="false"
    TITLE=""
    DESCRIPTION=""
    PRIORITY=""
    CREATED_TIME="0"
else
    TEMPLATE_FOUND="true"
    # Parse pipe-separated result (postgres -A -t output is usually pipe separated)
    # However, sdp_db_exec output format depends on the utility implementation.
    # Assuming standard psql default (pipe) or adjust parsing logic.
    
    TITLE=$(echo "$DB_RESULT" | cut -d'|' -f1)
    DESCRIPTION=$(echo "$DB_RESULT" | cut -d'|' -f2)
    PRIORITY=$(echo "$DB_RESULT" | cut -d'|' -f3)
    CREATED_TIME=$(echo "$DB_RESULT" | cut -d'|' -f4)
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "wrapper" > /dev/null && echo "true" || echo "false")

# Create JSON result safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use Python to escape strings for JSON to avoid syntax errors with descriptions containing quotes
python3 -c "
import json
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'template_found': $TEMPLATE_FOUND,
    'title': '''$TITLE'''.strip(),
    'description': '''$DESCRIPTION'''.strip(),
    'priority': '''$PRIORITY'''.strip(),
    'record_created_time': '''$CREATED_TIME'''.strip(),
    'app_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(data, indent=2))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="