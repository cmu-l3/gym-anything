#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_profile_count.txt 2>/dev/null || echo "0")

# 1. DATABASE VERIFICATION
# Check if the profile exists
echo "Querying database for Substitute profile..."
PROFILE_DATA=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -B -e "SELECT id, title FROM user_profiles WHERE title='Substitute' LIMIT 1" 2>/dev/null || true)

PROFILE_EXISTS="false"
PROFILE_ID=""
PROFILE_TITLE=""
PERMISSIONS_JSON="[]"

if [ -n "$PROFILE_DATA" ]; then
    PROFILE_EXISTS="true"
    PROFILE_ID=$(echo "$PROFILE_DATA" | awk '{print $1}')
    PROFILE_TITLE=$(echo "$PROFILE_DATA" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')
    
    echo "Profile found: ID=$PROFILE_ID, Title=$PROFILE_TITLE"

    # Check permissions for this profile
    # We look for records in profile_exceptions where can_use='Y'
    # We retrieve relevant modules to check for Attendance (allowed) and Grades (denied/missing)
    echo "Querying permissions..."
    PERMISSIONS_RAW=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -B -e "SELECT modname, can_use, can_edit FROM profile_exceptions WHERE profile_id='$PROFILE_ID'" 2>/dev/null || true)
    
    # Convert raw permissions lines to JSON array
    # Python is safer for JSON generation than bash string manipulation
    PERMISSIONS_JSON=$(python3 -c "
import sys, json
lines = sys.stdin.read().strip().split('\n')
perms = []
for line in lines:
    if line.strip():
        parts = line.split('\t')
        if len(parts) >= 2:
            perms.append({'modname': parts[0], 'can_use': parts[1], 'can_edit': parts[2] if len(parts)>2 else 'N'})
print(json.dumps(perms))
" <<< "$PERMISSIONS_RAW")
fi

# Get current profile count for anti-gaming check
CURRENT_COUNT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "SELECT COUNT(*) FROM user_profiles" 2>/dev/null || echo "0")

# 2. APPLICATION STATE
# Check if Chrome is still running
APP_RUNNING=$(pgrep -f "chrome" > /dev/null && echo "true" || echo "false")

# 3. EVIDENCE CAPTURE
# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. JSON EXPORT
# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "profile_exists": $PROFILE_EXISTS,
    "profile_id": "$PROFILE_ID",
    "profile_title": "$PROFILE_TITLE",
    "initial_profile_count": $INITIAL_COUNT,
    "current_profile_count": $CURRENT_COUNT,
    "permissions": $PERMISSIONS_JSON,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="