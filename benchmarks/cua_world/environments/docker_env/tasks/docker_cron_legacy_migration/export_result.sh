#!/bin/bash
echo "=== Exporting Docker Cron Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper to take screenshot
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
IMAGE_TAG="legacy-etl:latest"
TEST_CONTAINER="verifier-cron-test"
VERIFY_TOKEN="VERIFY_TOKEN_$(date +%s)"
VERIFY_ENDPOINT="http://verify.local"

# 1. Check if image exists
IMAGE_EXISTS="false"
IMAGE_CREATED_AFTER_START="false"

if docker inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    IMAGE_EXISTS="true"
    CREATED=$(docker inspect "$IMAGE_TAG" --format '{{.Created}}')
    CREATED_EPOCH=$(date -d "$CREATED" +%s 2>/dev/null || echo "0")
    if [ "$CREATED_EPOCH" -gt "$TASK_START" ]; then
        IMAGE_CREATED_AFTER_START="true"
    fi
fi

# 2. Functional Test: Run the container and wait for cron
LOGS_FOUND="false"
ENV_VARS_VISIBLE="false"
CONTAINER_KEPT_RUNNING="false"
CRON_PROCESS_FOUND="false"
LOG_CONTENT=""

if [ "$IMAGE_EXISTS" = "true" ]; then
    echo "Starting verification container..."
    # Kill any previous verify container
    docker rm -f "$TEST_CONTAINER" 2>/dev/null || true
    
    # Run container with specific test env vars
    docker run -d --name "$TEST_CONTAINER" \
        -e API_TOKEN="$VERIFY_TOKEN" \
        -e API_ENDPOINT="$VERIFY_ENDPOINT" \
        "$IMAGE_TAG"
    
    # Wait for container to settle (startup)
    sleep 5
    
    # Check if it crashed immediately
    if [ "$(docker inspect "$TEST_CONTAINER" --format '{{.State.Running}}')" == "true" ]; then
        echo "Container started, waiting 70s for cron schedule..."
        # Wait > 60s to ensure cron triggers at least once
        sleep 70
        
        # Check if still running
        if [ "$(docker inspect "$TEST_CONTAINER" --format '{{.State.Running}}')" == "true" ]; then
            CONTAINER_KEPT_RUNNING="true"
            
            # Check for cron process
            if docker top "$TEST_CONTAINER" | grep -q "cron"; then
                CRON_PROCESS_FOUND="true"
            fi
        fi
        
        # Capture logs
        LOG_CONTENT=$(docker logs "$TEST_CONTAINER" 2>&1 | tail -n 20)
        
        # Analyze logs
        if [ -n "$LOG_CONTENT" ]; then
            # Check if our specific token appears (proof of env var propagation)
            if echo "$LOG_CONTENT" | grep -q "$VERIFY_TOKEN"; then
                ENV_VARS_VISIBLE="true"
                LOGS_FOUND="true"
            # Check if *any* log output from script exists (even if vars unset)
            elif echo "$LOG_CONTENT" | grep -q "Starting ingestion"; then
                LOGS_FOUND="true"
            fi
        fi
    else
        echo "Container exited immediately."
        LOG_CONTENT=$(docker logs "$TEST_CONTAINER" 2>&1 | tail -n 10)
    fi
    
    # Cleanup
    docker rm -f "$TEST_CONTAINER" 2>/dev/null || true
fi

# 3. Export to JSON
cat > /tmp/task_result.json << EOF
{
    "image_exists": $IMAGE_EXISTS,
    "image_created_after_start": $IMAGE_CREATED_AFTER_START,
    "container_kept_running": $CONTAINER_KEPT_RUNNING,
    "cron_process_found": $CRON_PROCESS_FOUND,
    "logs_found": $LOGS_FOUND,
    "env_vars_visible": $ENV_VARS_VISIBLE,
    "log_sample": $(echo "$LOG_CONTENT" | jq -R -s '.'),
    "verify_token": "$VERIFY_TOKEN",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Export complete. Result:"
cat /tmp/task_result.json