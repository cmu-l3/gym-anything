#!/bin/bash
set -e
echo "=== Exporting create_agent_user results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for user 2001
# We select specific fields required for verification
echo "Querying Vicidial database for user 2001..."

# Check if user exists first
USER_EXISTS=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sN \
  -e "SELECT COUNT(*) FROM vicidial_users WHERE user='2001';" 2>/dev/null || echo "0")

USER_DATA="{}"

if [ "$USER_EXISTS" -eq "1" ]; then
    # Fetch fields as tab-separated values
    # Fields: user, pass, full_name, user_level, user_group, active, phone_login, phone_pass, hotkeys_active, scheduled_callbacks
    RAW_DATA=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sN -e \
      "SELECT user, pass, full_name, user_level, user_group, active, phone_login, phone_pass, hotkeys_active, scheduled_callbacks 
       FROM vicidial_users WHERE user='2001';" 2>/dev/null)
    
    # Parse into JSON manually to avoid dependencies
    # Using python to safely escape and format JSON
    USER_DATA=$(python3 -c "
import json
import sys

try:
    raw = '''$RAW_DATA'''
    if not raw.strip():
        print('{}')
        sys.exit(0)
        
    parts = raw.strip().split('\t')
    if len(parts) >= 10:
        data = {
            'user': parts[0],
            'pass': parts[1],
            'full_name': parts[2],
            'user_level': parts[3],
            'user_group': parts[4],
            'active': parts[5],
            'phone_login': parts[6],
            'phone_pass': parts[7],
            'hotkeys_active': parts[8],
            'scheduled_callbacks': parts[9]
        }
        print(json.dumps(data))
    else:
        print('{}')
except Exception as e:
    print('{}')
")
fi

# Get counts
INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sN \
  -e "SELECT COUNT(*) FROM vicidial_users;" 2>/dev/null || echo "0")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "user_exists": $([ "$USER_EXISTS" -eq "1" ] && echo "true" || echo "false"),
    "user_data": $USER_DATA,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="