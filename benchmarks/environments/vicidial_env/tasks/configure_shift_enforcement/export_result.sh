#!/bin/bash
echo "=== Exporting Configure Shift Enforcement Result ==="

# Source utils for screenshot
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# 2. Query Database for Result
# We run the queries inside the docker container and capture output

# Query 1: Shift Details
SHIFT_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT JSON_OBJECT('exists', COUNT(*), 'start_time', MAX(shift_start_time), 'length', MAX(shift_length)) FROM vicidial_shifts WHERE shift_id='SURVEY_EVE';" 2>/dev/null)

# Query 2: User Group Details
# Note: group_shifts is a space-delimited string usually wrapped in pipes like |SHIFT_ID|
GROUP_JSON=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT JSON_OBJECT('enforcement', shift_enforcement, 'group_shifts', group_shifts) FROM vicidial_user_groups WHERE user_group='SURVEY';" 2>/dev/null)

# 3. Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Construct Result JSON
# We combine the DB results into a single JSON structure
# If DB queries failed (empty), we provide defaults
if [ -z "$SHIFT_JSON" ]; then SHIFT_JSON='{"exists": 0}'; fi
if [ -z "$GROUP_JSON" ]; then GROUP_JSON='{"enforcement": "OFF", "group_shifts": ""}'; fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "shift_data": $SHIFT_JSON,
    "group_data": $GROUP_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to public location with read permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json