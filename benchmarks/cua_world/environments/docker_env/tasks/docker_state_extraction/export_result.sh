#!/bin/bash
# Export script for docker_state_extraction task
echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)

# Paths
PROJECT_DIR="/home/ga/projects/acme-legacy-app"
DOCKERFILE_PATH="$PROJECT_DIR/Dockerfile"
MANIFEST_PATH="/home/ga/Desktop/container_changes.txt"
IMAGE_TAG="acme-legacy-app:restored"

# 1. Check Dockerfile
DOCKERFILE_EXISTS=0
DOCKERFILE_CONTENT=""
HAS_CORRECT_FROM=0
if [ -f "$DOCKERFILE_PATH" ]; then
    DOCKERFILE_EXISTS=1
    DOCKERFILE_CONTENT=$(cat "$DOCKERFILE_PATH")
    if grep -q "python:3.11-slim" "$DOCKERFILE_PATH"; then
        HAS_CORRECT_FROM=1
    fi
fi

# 2. Check Image Existence
IMAGE_EXISTS=0
if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_TAG}$"; then
    IMAGE_EXISTS=1
fi

# 3. Functional Verification: Run the restored image
APP_HEALTHY=0
APP_RESPONSE=""
PKGS_INSTALLED=0
FILES_EXIST=0

if [ "$IMAGE_EXISTS" = "1" ]; then
    echo "Testing restored image..."
    TEST_CONTAINER="acme-test-$(date +%s)"
    
    # Run container (detach)
    docker run -d --name "$TEST_CONTAINER" -p 9090:8000 "$IMAGE_TAG"
    sleep 5
    
    # Check Health
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/health 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        APP_HEALTHY=1
    fi
    APP_RESPONSE=$(curl -s http://localhost:9090/health 2>/dev/null | head -c 200)

    # Check Internal State (Packages & Files)
    # Check Python packages
    PIP_LIST=$(docker exec "$TEST_CONTAINER" pip list 2>/dev/null || echo "")
    if echo "$PIP_LIST" | grep -q "flask" && echo "$PIP_LIST" | grep -q "gunicorn"; then
        PKGS_INSTALLED=1
    fi
    
    # Check System packages
    if docker exec "$TEST_CONTAINER" which curl >/dev/null && \
       docker exec "$TEST_CONTAINER" which vim >/dev/null; then
        # Increment score internal logic handled by python verifier, just flag here
        SYS_PKGS_INSTALLED=1
    else
        SYS_PKGS_INSTALLED=0
    fi

    # Check Files
    if docker exec "$TEST_CONTAINER" test -f /app/inventory_api.py && \
       docker exec "$TEST_CONTAINER" test -f /app/config.json; then
        FILES_EXIST=1
    fi

    # Cleanup
    docker rm -f "$TEST_CONTAINER" 2>/dev/null || true
else
    SYS_PKGS_INSTALLED=0
fi

# 4. Check Manifest
MANIFEST_EXISTS=0
MANIFEST_SIZE=0
if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_EXISTS=1
    MANIFEST_SIZE=$(wc -c < "$MANIFEST_PATH")
fi

# 5. Screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_final.png
else
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
fi

# 6. JSON Export
cat > /tmp/task_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "export_time": $EXPORT_TIME,
    "dockerfile_exists": $DOCKERFILE_EXISTS,
    "has_correct_from": $HAS_CORRECT_FROM,
    "image_exists": $IMAGE_EXISTS,
    "app_healthy": $APP_HEALTHY,
    "app_response_preview": "$(echo $APP_RESPONSE | tr -d '"')",
    "pkgs_installed": $PKGS_INSTALLED,
    "sys_pkgs_installed": $SYS_PKGS_INSTALLED,
    "files_exist": $FILES_EXIST,
    "manifest_exists": $MANIFEST_EXISTS,
    "manifest_size": $MANIFEST_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
JSONEOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json