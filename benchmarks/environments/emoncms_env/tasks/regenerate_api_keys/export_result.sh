#!/bin/bash
# Export script for regenerate_api_keys task

source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# 1. Record End Time and Take Screenshot
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
take_screenshot /tmp/task_final_state.png

# 2. Load the OLD keys (Ground Truth for "Old")
OLD_WRITE_KEY=""
OLD_READ_KEY=""
if [ -f /tmp/old_apikeys.txt ]; then
    OLD_WRITE_KEY=$(grep '^WRITE_KEY=' /tmp/old_apikeys.txt | cut -d= -f2 | tr -d '[:space:]')
    OLD_READ_KEY=$(grep '^READ_KEY=' /tmp/old_apikeys.txt | cut -d= -f2 | tr -d '[:space:]')
fi

# 3. Get CURRENT keys from Database (Ground Truth for "New")
CUR_WRITE_KEY=$(get_apikey_write)
CUR_READ_KEY=$(get_apikey_read)

# 4. Check Agent's Output File
FILE_PATH="/home/ga/new_apikeys.txt"
FILE_EXISTS="false"
FILE_WRITE_KEY=""
FILE_READ_KEY=""

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    # Extract keys from file (tolerant of spacing)
    FILE_WRITE_KEY=$(grep -i "WRITE_KEY" "$FILE_PATH" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    FILE_READ_KEY=$(grep -i "READ_KEY" "$FILE_PATH" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# 5. Verify Revocation: Test OLD keys against API
# If they work, revocation failed.
# We expect an error or empty result, NOT a valid JSON list.
OLD_WRITE_WORKS="false"
OLD_READ_WORKS="false"

# Test Old Write Key
RESP_W=$(curl -s --max-time 5 "${EMONCMS_URL}/feed/list.json?apikey=${OLD_WRITE_KEY}")
# Valid response is a JSON array e.g. [{"id":...}]
if echo "$RESP_W" | jq -e '. | type == "array"' >/dev/null 2>&1; then
    OLD_WRITE_WORKS="true"
fi

# Test Old Read Key
RESP_R=$(curl -s --max-time 5 "${EMONCMS_URL}/feed/list.json?apikey=${OLD_READ_KEY}")
if echo "$RESP_R" | jq -e '. | type == "array"' >/dev/null 2>&1; then
    OLD_READ_WORKS="true"
fi

# 6. Verify New Keys: Test CURRENT DB keys against API
# They SHOULD work.
NEW_WRITE_WORKS="false"
NEW_READ_WORKS="false"

RESP_NW=$(curl -s --max-time 5 "${EMONCMS_URL}/feed/list.json?apikey=${CUR_WRITE_KEY}")
if echo "$RESP_NW" | jq -e '. | type == "array"' >/dev/null 2>&1; then
    NEW_WRITE_WORKS="true"
fi

RESP_NR=$(curl -s --max-time 5 "${EMONCMS_URL}/feed/list.json?apikey=${CUR_READ_KEY}")
if echo "$RESP_NR" | jq -e '. | type == "array"' >/dev/null 2>&1; then
    NEW_READ_WORKS="true"
fi

# 7. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "old_keys": {
        "write": "$OLD_WRITE_KEY",
        "read": "$OLD_READ_KEY",
        "write_still_works": $OLD_WRITE_WORKS,
        "read_still_works": $OLD_READ_WORKS
    },
    "current_db_keys": {
        "write": "$CUR_WRITE_KEY",
        "read": "$CUR_READ_KEY",
        "write_works": $NEW_WRITE_WORKS,
        "read_works": $NEW_READ_WORKS
    },
    "agent_file": {
        "exists": $FILE_EXISTS,
        "write_key_content": "$FILE_WRITE_KEY",
        "read_key_content": "$FILE_READ_KEY"
    },
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="