#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Target Patient Status (Marcus Wellington - P00300)
# We expect 404 Not Found OR _deleted: true
TARGET_ID="patient_p1_P00300"
TARGET_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${TARGET_ID}")
TARGET_DELETED="false"

if [ "$TARGET_HTTP_CODE" = "404" ]; then
    TARGET_DELETED="true"
    echo "Target patient not found (404) - Deletion confirmed."
else
    # Check if marked as deleted but still accessible (tombstone)
    IS_DELETED_FLAG=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${TARGET_ID}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_deleted', False))" 2>/dev/null)
    if [ "$IS_DELETED_FLAG" = "True" ] || [ "$IS_DELETED_FLAG" = "true" ]; then
        TARGET_DELETED="true"
        echo "Target patient marked _deleted: true."
    else
        echo "Target patient still exists."
    fi
fi

# 2. Check Control Patient Status (Elena Vasquez - P00100)
# MUST exist (200 OK)
CONTROL_ID="patient_p1_P00100"
CONTROL_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${CONTROL_ID}")
CONTROL_EXISTS="false"

if [ "$CONTROL_HTTP_CODE" = "200" ]; then
    CONTROL_EXISTS="true"
else
    echo "WARNING: Control patient missing!"
fi

# 3. Check Pre-condition
TARGET_EXISTED_AT_START=$(cat /tmp/target_existed_at_start.txt 2>/dev/null || echo "false")

# 4. Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_existed_at_start": $TARGET_EXISTED_AT_START,
    "target_deleted": $TARGET_DELETED,
    "control_exists": $CONTROL_EXISTS,
    "target_http_code": "$TARGET_HTTP_CODE",
    "control_http_code": "$CONTROL_HTTP_CODE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="