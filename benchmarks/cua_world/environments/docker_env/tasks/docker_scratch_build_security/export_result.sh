#!/bin/bash
echo "=== Exporting Secure Scratch Build Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
IMAGE_TAG="payment-validator:secure"

# Initialize variables
IMAGE_EXISTS=0
IMAGE_SIZE_BYTES=0
IMAGE_USER=""
IS_SCRATCH=0
HTTPS_CHECK_PASSED=0
SHELL_EXISTS=1 # Assume shell exists until proven otherwise
CREATED_TIMESTAMP=0

# 1. Check if image exists
if docker inspect "$IMAGE_TAG" > /dev/null 2>&1; then
    IMAGE_EXISTS=1
    
    # Get Metadata
    IMAGE_SIZE_BYTES=$(docker inspect "$IMAGE_TAG" --format '{{.Size}}')
    IMAGE_USER=$(docker inspect "$IMAGE_TAG" --format '{{.Config.User}}')
    CREATED_STR=$(docker inspect "$IMAGE_TAG" --format '{{.Created}}')
    CREATED_TIMESTAMP=$(date -d "$CREATED_STR" +%s 2>/dev/null || echo "0")

    # 2. Check for Shell (Negative Test)
    # If the image is truly scratch/distroless, /bin/sh should NOT exist.
    # We expect this command to FAIL (exit code != 0).
    if ! docker run --rm --entrypoint "/bin/sh" "$IMAGE_TAG" -c "echo hello" > /dev/null 2>&1; then
        SHELL_EXISTS=0
        echo "Confirmed: No shell found in image."
    else
        echo "Warning: Shell found in image."
    fi

    # 3. Functional Test (HTTPS & Execution)
    # We run the container detached, wait 5s, check logs, then stop it.
    CONTAINER_ID=$(docker run -d --rm "$IMAGE_TAG")
    sleep 5
    
    LOGS=$(docker logs "$CONTAINER_ID" 2>&1)
    
    if echo "$LOGS" | grep -q "HTTPS check passed"; then
        HTTPS_CHECK_PASSED=1
    fi
    
    # Check if it crashed
    STATE=$(docker inspect "$CONTAINER_ID" --format '{{.State.Running}}' 2>/dev/null || echo "false")
    if [ "$STATE" = "false" ]; then
        EXIT_CODE=$(docker inspect "$CONTAINER_ID" --format '{{.State.ExitCode}}' 2>/dev/null || echo "1")
        echo "Container crashed with exit code $EXIT_CODE"
    else
        echo "Container is running successfully."
        docker kill "$CONTAINER_ID" > /dev/null 2>&1 || true
    fi
fi

# Determine if created during task
CREATED_DURING_TASK=0
if [ "$CREATED_TIMESTAMP" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK=1
fi

cat > /tmp/task_result.json << EOF
{
    "image_exists": $IMAGE_EXISTS,
    "image_size_bytes": $IMAGE_SIZE_BYTES,
    "image_user": "$IMAGE_USER",
    "shell_exists": $SHELL_EXISTS,
    "https_check_passed": $HTTPS_CHECK_PASSED,
    "created_during_task": $CREATED_DURING_TASK,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json