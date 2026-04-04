#!/bin/bash
set -e

echo "=== Exporting task results: create_user_group_permissions ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_group_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Database Verification ---

# Query the user group
echo "Querying Vicidial database for PRMSALES group..."
QUERY_RESULT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT user_group, group_name, group_level, forced_timeclock_login, shift_enforcement, allowed_campaigns FROM vicidial_user_groups WHERE user_group = 'PRMSALES';" 2>/dev/null || echo "")

# Parse fields (tab-separated from MySQL -N output)
# Note: Empty result implies group doesn't exist
if [ -n "$QUERY_RESULT" ]; then
    GROUP_EXISTS="true"
    DB_USER_GROUP=$(echo "$QUERY_RESULT" | awk -F'\t' '{print $1}')
    DB_GROUP_NAME=$(echo "$QUERY_RESULT" | awk -F'\t' '{print $2}')
    DB_GROUP_LEVEL=$(echo "$QUERY_RESULT" | awk -F'\t' '{print $3}')
    DB_FORCED_TIMECLOCK=$(echo "$QUERY_RESULT" | awk -F'\t' '{print $4}')
    DB_SHIFT_ENFORCEMENT=$(echo "$QUERY_RESULT" | awk -F'\t' '{print $5}')
    DB_ALLOWED_CAMPAIGNS=$(echo "$QUERY_RESULT" | awk -F'\t' '{print $6}')
else
    GROUP_EXISTS="false"
    DB_USER_GROUP=""
    DB_GROUP_NAME=""
    DB_GROUP_LEVEL=""
    DB_FORCED_TIMECLOCK=""
    DB_SHIFT_ENFORCEMENT=""
    DB_ALLOWED_CAMPAIGNS=""
fi

# Check current count for anti-gaming (did count increase?)
CURRENT_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_user_groups;" 2>/dev/null || echo "0")

COUNT_INCREASED="false"
if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    COUNT_INCREASED="true"
fi

# Escape strings for JSON
ESC_GROUP_NAME=$(echo "$DB_GROUP_NAME" | sed 's/"/\\"/g')
ESC_ALLOWED_CAMPAIGNS=$(echo "$DB_ALLOWED_CAMPAIGNS" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "group_exists": $GROUP_EXISTS,
    "db_data": {
        "user_group": "$DB_USER_GROUP",
        "group_name": "$ESC_GROUP_NAME",
        "group_level": "$DB_GROUP_LEVEL",
        "forced_timeclock_login": "$DB_FORCED_TIMECLOCK",
        "shift_enforcement": "$DB_SHIFT_ENFORCEMENT",
        "allowed_campaigns": "$ESC_ALLOWED_CAMPAIGNS"
    },
    "anti_gaming": {
        "initial_count": $INITIAL_COUNT,
        "current_count": $CURRENT_COUNT,
        "count_increased": $COUNT_INCREASED
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="