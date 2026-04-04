#!/bin/bash
set -e
echo "=== Exporting create_survey_call_script results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Query the database for the specific script
echo "Querying Vicidial database for script NPS_TELECOM_2025..."

# complex query to get fields safely as hex to avoid quoting issues, then handled in python or jq?
# Easier: Get fields one by one or use python within the container if available. 
# We'll use docker exec with simple select and format it as JSON using python on the host side.

SCRIPT_EXISTS="false"
SCRIPT_DATA="{}"

# Check if script exists
COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sN -e \
    "SELECT COUNT(*) FROM vicidial_scripts WHERE script_id='NPS_TELECOM_2025';" 2>/dev/null || echo "0")

if [ "$COUNT" -ge 1 ]; then
    SCRIPT_EXISTS="true"
    
    # Extract fields safely using python inside the export script to handle special chars/newlines
    # We use python to run the mysql command and format JSON to avoid bash string hell
    SCRIPT_DATA=$(python3 -c "
import subprocess
import json
import sys

def get_db_field(field):
    cmd = ['docker', 'exec', 'vicidial', 'mysql', '-ucron', '-p1234', '-D', 'asterisk', '-sN', '-e', f'SELECT {{field}} FROM vicidial_scripts WHERE script_id=\"NPS_TELECOM_2025\"']
    try:
        return subprocess.check_output(cmd).decode('utf-8', errors='ignore').strip()
    except:
        return ''

data = {
    'script_id': get_db_field('script_id'),
    'script_name': get_db_field('script_name'),
    'script_comments': get_db_field('script_comments'),
    'script_text': get_db_field('script_text'),
    'active': get_db_field('active')
}
print(json.dumps(data))
")
fi

# Get total script count for anti-gaming
FINAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sN -e \
    "SELECT COUNT(*) FROM vicidial_scripts;" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_script_count.txt 2>/dev/null || echo "0")

# Check if browser is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_exists": $SCRIPT_EXISTS,
    "script_data": $SCRIPT_DATA,
    "initial_script_count": $INITIAL_COUNT,
    "final_script_count": $FINAL_COUNT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to accessible location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="