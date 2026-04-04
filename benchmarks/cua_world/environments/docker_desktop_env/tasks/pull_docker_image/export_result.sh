#!/bin/bash
# Export script for pull_docker_image task (post_task hook)
# Gathers verification data and saves to JSON

echo "=== Exporting pull_docker_image task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get initial image count
INITIAL_COUNT=$(cat /tmp/initial_image_count 2>/dev/null || echo "0")

# Get current image count
CURRENT_COUNT=$(get_image_count)

# Check if target image exists
TARGET_IMAGE="python:3.11-slim"
IMAGE_FOUND="false"
IMAGE_ID=""
IMAGE_SIZE=""
IMAGE_CREATED=""

# Check for exact match first
if docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -qx "$TARGET_IMAGE"; then
    IMAGE_FOUND="true"
    # Use tab as delimiter for reliable parsing
    IMAGE_ID=$(docker images "$TARGET_IMAGE" --format '{{.ID}}' 2>/dev/null | head -1)
    IMAGE_SIZE=$(docker images "$TARGET_IMAGE" --format '{{.Size}}' 2>/dev/null | head -1)
    IMAGE_CREATED=$(docker images "$TARGET_IMAGE" --format '{{.CreatedSince}}' 2>/dev/null | head -1)
fi

# Also check for python:3.11-slim variants
if [ "$IMAGE_FOUND" = "false" ]; then
    # Check for python image with 3.11-slim tag
    if docker images "python" --format '{{.Tag}}' 2>/dev/null | grep -q "3.11-slim"; then
        IMAGE_FOUND="true"
        IMAGE_ID=$(docker images "python:3.11-slim" --format '{{.ID}}' 2>/dev/null | head -1)
        IMAGE_SIZE=$(docker images "python:3.11-slim" --format '{{.Size}}' 2>/dev/null | head -1)
        IMAGE_CREATED=$(docker images "python:3.11-slim" --format '{{.CreatedSince}}' 2>/dev/null | head -1)
    fi
fi

# Get list of all python images (for debugging)
PYTHON_IMAGES=$(docker images "python" --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# Get list of all images
ALL_IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | head -20 | tr '\n' ',' | sed 's/,$//')

# Check if Docker Desktop is running (check multiple possible process names)
DOCKER_DESKTOP_RUNNING="false"
if pgrep -f "com.docker.backend" > /dev/null 2>&1 || \
   pgrep -f "/opt/docker-desktop/Docker" > /dev/null 2>&1; then
    DOCKER_DESKTOP_RUNNING="true"
fi

# Check if Docker daemon is working
DOCKER_DAEMON_READY="false"
if timeout 5 docker info > /dev/null 2>&1; then
    DOCKER_DAEMON_READY="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task": "pull_docker_image",
    "target_image": "$TARGET_IMAGE",
    "image_found": $IMAGE_FOUND,
    "image_id": "$IMAGE_ID",
    "image_size": "$IMAGE_SIZE",
    "image_created": "$IMAGE_CREATED",
    "initial_image_count": $INITIAL_COUNT,
    "current_image_count": $CURRENT_COUNT,
    "python_images": "$PYTHON_IMAGES",
    "all_images_sample": "$ALL_IMAGES",
    "docker_desktop_running": $DOCKER_DESKTOP_RUNNING,
    "docker_daemon_ready": $DOCKER_DAEMON_READY,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with fallbacks
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
