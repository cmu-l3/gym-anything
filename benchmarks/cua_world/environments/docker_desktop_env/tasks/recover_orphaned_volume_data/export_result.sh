#!/bin/bash
echo "=== Exporting recover_orphaned_volume_data result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# --- Verification Logic ---

CONTAINER_NAME="recovery-env"
EXPECTED_MOUNT="/workspace"
TARGET_FILE="PROJECT_X_BLUEPRINT.md"
SECRET_FILE="/home/ga/.hidden_task_data/secret_token.txt"

# 1. Check if container exists and is running
CONTAINER_RUNNING="false"
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" == "true" ]; then
    CONTAINER_RUNNING="true"
fi

# 2. Check for volume mount at /workspace
VOLUME_MOUNTED="false"
MOUNT_SOURCE=""
if [ "$CONTAINER_RUNNING" == "true" ]; then
    # Parse mounts to find if /workspace is a destination
    # We look for Destination: /workspace
    if docker inspect "$CONTAINER_NAME" | grep -q "\"Destination\": \"$EXPECTED_MOUNT\""; then
        VOLUME_MOUNTED="true"
        # Extract source for debugging log (not strictly needed for verification but good for feedback)
        MOUNT_SOURCE=$(docker inspect --format='{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}' "$CONTAINER_NAME")
    fi
fi

# 3. Verify Content (The most critical step)
# We exec into the container to read the file. This proves the correct volume is mounted.
CONTENT_MATCH="false"
FILE_FOUND="false"
ACTUAL_TOKEN="none"
EXPECTED_TOKEN="unknown"

if [ -f "$SECRET_FILE" ]; then
    EXPECTED_TOKEN=$(cat "$SECRET_FILE" | tr -d '\n\r')
fi

if [ "$CONTAINER_RUNNING" == "true" ]; then
    # check if file exists
    if docker exec "$CONTAINER_NAME" test -f "$EXPECTED_MOUNT/$TARGET_FILE" 2>/dev/null; then
        FILE_FOUND="true"
        # read content
        FILE_CONTENT=$(docker exec "$CONTAINER_NAME" cat "$EXPECTED_MOUNT/$TARGET_FILE" 2>/dev/null)
        
        # Check if secret token is inside
        if echo "$FILE_CONTENT" | grep -q "$EXPECTED_TOKEN"; then
            CONTENT_MATCH="true"
            ACTUAL_TOKEN="match_hidden"
        else
            ACTUAL_TOKEN="mismatch"
        fi
    fi
fi

# 4. Anti-gaming: Check timestamp
# We already generate a unique token per run, so simply "copying" a file from a previous run wouldn't work.
# But we can also check if the container was created after task start.
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONTAINER_CREATED_TS=0
CREATED_AFTER_START="false"

if [ "$CONTAINER_RUNNING" == "true" ]; then
    CREATED_STR=$(docker inspect -f '{{.Created}}' "$CONTAINER_NAME" 2>/dev/null)
    # Convert ISO timestamp to unix (requires date parsing, might be tricky in minimal shell)
    # Alternatively, we trust the unique token verification as primary anti-gaming.
    # But let's try a simple check if date is available
    CONTAINER_CREATED_TS=$(date -d "$CREATED_STR" +%s 2>/dev/null || echo "0")
    if [ "$CONTAINER_CREATED_TS" -gt "$TASK_START" ]; then
        CREATED_AFTER_START="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "container_running": $CONTAINER_RUNNING,
    "volume_mounted": $VOLUME_MOUNTED,
    "file_found": $FILE_FOUND,
    "content_match": $CONTENT_MATCH,
    "created_after_start": $CREATED_AFTER_START,
    "mount_source": "$MOUNT_SOURCE",
    "timestamp": "$(date -Iseconds)"
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