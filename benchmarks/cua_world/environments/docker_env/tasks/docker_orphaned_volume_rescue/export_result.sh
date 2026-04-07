#!/bin/bash
echo "=== Exporting Volume Rescue Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Check if the container is running
CONTAINER_NAME="recovery-service"
IS_RUNNING=0
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    IS_RUNNING=1
fi

# 2. Check if the file exists inside the container and read it
FILE_EXISTS=0
ACTUAL_CONTENT=""
TARGET_PATH="/app/data/uploads/critical_manifest.json"

if [ "$IS_RUNNING" -eq 1 ]; then
    if docker exec "$CONTAINER_NAME" test -f "$TARGET_PATH" 2>/dev/null; then
        FILE_EXISTS=1
        # Read content (limited to 500 bytes to prevent huge output)
        ACTUAL_CONTENT=$(docker exec "$CONTAINER_NAME" cat "$TARGET_PATH" 2>/dev/null | head -c 500)
    fi
fi

# 3. Verify if the Correct Volume ID was mounted (Strict Check)
# This distinguishes between "I found the volume and mounted it" vs "I copied the file to a new volume"
MOUNTED_VOLUME_CORRECT=0
EXPECTED_VOL_NAME=$(cat /tmp/target_volume_name.txt 2>/dev/null || echo "unknown_vol")

if [ "$IS_RUNNING" -eq 1 ]; then
    # Inspect mounts to find if the expected volume is mounted to /app/data
    # We look for Source matching the volume name and Destination matching /app/data
    if docker inspect "$CONTAINER_NAME" --format '{{json .Mounts}}' | grep -q "$EXPECTED_VOL_NAME"; then
        MOUNTED_VOLUME_CORRECT=1
    fi
fi

# 4. Get Expected Content for verification
EXPECTED_CONTENT=$(cat /tmp/expected_content_string.txt 2>/dev/null || echo "")

# Take final screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_final.png
fi

# Generate Result JSON
cat > /tmp/volume_rescue_result.json <<EOF
{
    "container_running": $IS_RUNNING,
    "file_exists": $FILE_EXISTS,
    "actual_content": $(echo "$ACTUAL_CONTENT" | jq -R .),
    "expected_content": $(echo "$EXPECTED_CONTENT" | jq -R .),
    "mounted_correct_volume_id": $MOUNTED_VOLUME_CORRECT,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/volume_rescue_result.json"
cat /tmp/volume_rescue_result.json