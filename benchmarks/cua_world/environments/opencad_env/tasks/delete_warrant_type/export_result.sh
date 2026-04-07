#!/bin/bash
echo "=== Exporting delete_warrant_type result ==="

source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Load Context
if [ -f "/tmp/warrant_table_name.txt" ]; then
    TABLE_NAME=$(cat /tmp/warrant_table_name.txt)
else
    # Fallback detection
    TABLE_NAME=$(docker exec opencad-db mysql -u opencad -popencadpass opencad -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema='opencad' AND table_name LIKE '%warrant%type%' LIMIT 1")
    if [ -z "$TABLE_NAME" ]; then TABLE_NAME="warrant_types"; fi
fi

INITIAL_COUNT=$(cat /tmp/initial_warrant_count.txt 2>/dev/null || echo "0")
TARGET="Civil Contempt"

# 3. Check Current State
echo "Checking if '$TARGET' exists in $TABLE_NAME..."
TARGET_EXISTS=$(docker exec opencad-db mysql -u opencad -popencadpass opencad -N -e "SELECT COUNT(*) FROM $TABLE_NAME WHERE warrant_type='$TARGET'")

echo "Getting current total count..."
CURRENT_COUNT=$(docker exec opencad-db mysql -u opencad -popencadpass opencad -N -e "SELECT COUNT(*) FROM $TABLE_NAME")

# 4. Check App State
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then APP_RUNNING="true"; fi

# 5. Export JSON
# We use a temp file to avoid permission issues, then move it
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_exists": $TARGET_EXISTS,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "table_name": "$TABLE_NAME",
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe move
rm -f /tmp/delete_warrant_type_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/delete_warrant_type_result.json
chmod 666 /tmp/delete_warrant_type_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/delete_warrant_type_result.json"
cat /tmp/delete_warrant_type_result.json
echo "=== Export complete ==="