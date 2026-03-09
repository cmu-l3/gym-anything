#!/bin/bash
set -e
echo "=== Exporting create_restricted_api_user result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Query the database for the specific user
# We select all relevant fields to verify configuration
echo "Querying Vicidial database..."
USER_DATA_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "
SELECT 
    user, 
    pass, 
    full_name, 
    user_level, 
    user_group, 
    api_only_user, 
    view_reports, 
    modify_leads, 
    modify_users, 
    modify_campaigns 
FROM vicidial_users 
WHERE user='leadview_api'
" | python3 -c '
import sys, json
lines = sys.stdin.readlines()
if not lines:
    print(json.dumps(None))
else:
    # Headers are not included in -N output, so we map by known index
    # 0:user, 1:pass, 2:full_name, 3:level, 4:group, 5:api_only, 6:view_reports, 7:mod_leads, 8:mod_users, 9:mod_campaigns
    parts = lines[0].strip().split("\t")
    if len(parts) >= 10:
        data = {
            "user": parts[0],
            "pass": parts[1],
            "full_name": parts[2],
            "user_level": parts[3],
            "user_group": parts[4],
            "api_only_user": parts[5],
            "view_reports": parts[6],
            "modify_leads": parts[7],
            "modify_users": parts[8],
            "modify_campaigns": parts[9]
        }
        print(json.dumps(data))
    else:
        print(json.dumps(None))
' || echo "null")

# Get current user count
CURRENT_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT count(*) FROM vicidial_users" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")

# Check if browser is running
BROWSER_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "user_data": $USER_DATA_JSON,
    "browser_running": $BROWSER_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="