#!/bin/bash
echo "=== Exporting multistage_dockerfile_optimization Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

APP_DIR="/home/ga/todo-app"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# --- Check Dockerfile modification ---
DOCKERFILE="$APP_DIR/Dockerfile"
DOCKERFILE_MODIFIED="false"
DOCKERFILE_MTIME=$(stat -c %Y "$DOCKERFILE" 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_dockerfile_mtime 2>/dev/null || echo "0")
if [ "$DOCKERFILE_MTIME" -gt "$INITIAL_MTIME" ]; then
    DOCKERFILE_MODIFIED="true"
fi

# --- Check multi-stage: count FROM statements ---
FROM_COUNT=0
IS_MULTISTAGE="false"
if [ -f "$DOCKERFILE" ]; then
    FROM_COUNT=$(grep -ci "^FROM" "$DOCKERFILE" 2>/dev/null || echo "0")
    if [ "$FROM_COUNT" -ge 2 ]; then
        IS_MULTISTAGE="true"
    fi
fi

# --- Check optimized image exists ---
OPTIMIZED_EXISTS="false"
OPTIMIZED_SIZE_MB=0
if docker image inspect todo-app:optimized >/dev/null 2>&1; then
    OPTIMIZED_EXISTS="true"
    OPTIMIZED_BYTES=$(docker inspect todo-app:optimized --format='{{.Size}}' 2>/dev/null || echo "0")
    OPTIMIZED_SIZE_MB=$((OPTIMIZED_BYTES / 1048576))
fi

# --- Get original image size ---
ORIGINAL_SIZE_MB=$(cat /tmp/original_image_size_mb 2>/dev/null || echo "0")
# Also try live
if docker image inspect todo-app:original >/dev/null 2>&1; then
    LIVE_ORIG=$(docker inspect todo-app:original --format='{{.Size}}' 2>/dev/null || echo "0")
    LIVE_ORIG_MB=$((LIVE_ORIG / 1048576))
    if [ "$LIVE_ORIG_MB" -gt 0 ]; then
        ORIGINAL_SIZE_MB="$LIVE_ORIG_MB"
    fi
fi

# --- Test app functionality by running the optimized container ---
APP_HTTP_CODE="000"
CONTAINER_STARTED="false"
if [ "$OPTIMIZED_EXISTS" = "true" ]; then
    # Remove any existing test container
    docker rm -f todo-test-run 2>/dev/null || true
    # Run the optimized image
    docker run -d --name todo-test-run -p 13000:3000 todo-app:optimized 2>/dev/null
    if [ $? -eq 0 ]; then
        CONTAINER_STARTED="true"
        sleep 5
        for i in 1 2 3 4 5; do
            CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 http://localhost:13000/health 2>/dev/null || echo "000")
            if [ "$CODE" = "200" ]; then
                APP_HTTP_CODE="$CODE"
                break
            fi
            # Try root path too
            CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 http://localhost:13000/ 2>/dev/null || echo "000")
            if [ "$CODE" = "200" ]; then
                APP_HTTP_CODE="$CODE"
                break
            fi
            sleep 3
        done
        docker rm -f todo-test-run 2>/dev/null || true
    fi
fi

# --- Write result JSON ---
cat > /tmp/multistage_dockerfile_optimization_result.json << JSONEOF
{
    "dockerfile_modified": $DOCKERFILE_MODIFIED,
    "is_multistage": $IS_MULTISTAGE,
    "from_count": $FROM_COUNT,
    "optimized_image_exists": $OPTIMIZED_EXISTS,
    "optimized_size_mb": $OPTIMIZED_SIZE_MB,
    "original_size_mb": $ORIGINAL_SIZE_MB,
    "app_http_code": "$APP_HTTP_CODE",
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "=== Export Complete ==="
cat /tmp/multistage_dockerfile_optimization_result.json
