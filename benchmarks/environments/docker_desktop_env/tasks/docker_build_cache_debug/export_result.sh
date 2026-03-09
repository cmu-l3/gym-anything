#!/bin/bash
echo "=== Exporting Docker Build Cache Debug Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

PROJECT_DIR="/home/ga/build-project"
DOCKERFILE="$PROJECT_DIR/Dockerfile"
DOCKERIGNORE="$PROJECT_DIR/.dockerignore"
RESULT_JSON="/tmp/task_result.json"

# 1. Anti-gaming checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/initial_dockerfile_hash.txt 2>/dev/null | awk '{print $1}')
CURRENT_HASH=$(md5sum "$DOCKERFILE" 2>/dev/null | awk '{print $1}')

DOCKERFILE_MODIFIED="false"
if [ "$INITIAL_HASH" != "$CURRENT_HASH" ]; then
    DOCKERFILE_MODIFIED="true"
fi

DOCKERFILE_MTIME=$(stat -c %Y "$DOCKERFILE" 2>/dev/null || echo "0")
MODIFIED_DURING_TASK="false"
if [ "$DOCKERFILE_MTIME" -gt "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
fi

# 2. Static Analysis of Dockerfile
# We need to find the line numbers of specific instructions
# Use 'grep -n' to find line numbers. If not found, return 9999 (bottom).
# If multiple, take the first one.

# Find where 'apt-get install' happens
APT_LINE=$(grep -n "apt-get.*install" "$DOCKERFILE" | head -1 | cut -d: -f1 || echo "9999")

# Find where 'COPY ... requirements.txt' happens
# Valid patterns: "COPY requirements.txt .", "COPY ./requirements.txt /app", etc.
COPY_REQ_LINE=$(grep -nE "COPY\s+.*requirements\.txt" "$DOCKERFILE" | head -1 | cut -d: -f1 || echo "9999")

# Find where 'pip install' happens
PIP_LINE=$(grep -nE "RUN\s+pip\s+install" "$DOCKERFILE" | head -1 | cut -d: -f1 || echo "9999")

# Find where source code is copied (COPY . .)
# We look for "COPY . ." or "COPY . /app"
COPY_SRC_LINE=$(grep -nE "COPY\s+\.\s+(\.|/app)" "$DOCKERFILE" | head -1 | cut -d: -f1 || echo "9999")

# 3. Check .dockerignore
DOCKERIGNORE_EXISTS="false"
IGNORES_GIT="false"
IGNORES_PYCACHE="false"

if [ -f "$DOCKERIGNORE" ]; then
    DOCKERIGNORE_EXISTS="true"
    if grep -qE "^\.git/?$" "$DOCKERIGNORE" || grep -qE "^\*\.git" "$DOCKERIGNORE"; then
        IGNORES_GIT="true"
    fi
    if grep -q "pycache" "$DOCKERIGNORE" || grep -q "\*.pyc" "$DOCKERIGNORE"; then
        IGNORES_PYCACHE="true"
    fi
fi

# 4. Check Image Build
IMAGE_TAG="build-project:optimized"
IMAGE_EXISTS="false"
IMAGE_ID=""

if docker images "$IMAGE_TAG" --format "{{.ID}}" | grep -q .; then
    IMAGE_EXISTS="true"
    IMAGE_ID=$(docker images "$IMAGE_TAG" --format "{{.ID}}")
fi

# 5. Check Image Provenance/History
# Verify that the image actually contains the expected layers (apt, pip)
# and wasn't just tagged from the base image.
HAS_PIP_LAYER="false"
HAS_APT_LAYER="false"
if [ "$IMAGE_EXISTS" = "true" ]; then
    HISTORY=$(docker history "$IMAGE_TAG" --no-trunc 2>/dev/null)
    if echo "$HISTORY" | grep -q "pip install"; then
        HAS_PIP_LAYER="true"
    fi
    if echo "$HISTORY" | grep -q "apt-get"; then
        HAS_APT_LAYER="true"
    fi
fi

# 6. Check Functionality (Container Run)
# Try to start the container if not running, or check if user left it running
CONTAINER_WORKS="false"
TEST_CONTAINER_NAME="verifier-test-container"

# First check if user left a container running on port 5000
USER_CONTAINER=$(docker ps --format "{{.Names}}" --filter "publish=5000" | head -1)
if [ -n "$USER_CONTAINER" ]; then
    # Test user's container
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/health || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        CONTAINER_WORKS="true"
    fi
elif [ "$IMAGE_EXISTS" = "true" ]; then
    # Try to spin up our own test container
    docker rm -f "$TEST_CONTAINER_NAME" 2>/dev/null || true
    docker run -d --name "$TEST_CONTAINER_NAME" -p 5000:5000 "$IMAGE_TAG" > /dev/null 2>&1
    
    # Wait for startup
    sleep 3
    
    # Check health
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/health || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        CONTAINER_WORKS="true"
    fi
    
    # Cleanup
    docker rm -f "$TEST_CONTAINER_NAME" > /dev/null 2>&1 || true
fi

# Generate JSON
cat > "$RESULT_JSON" << EOF
{
    "dockerfile_modified": $DOCKERFILE_MODIFIED,
    "modified_during_task": $MODIFIED_DURING_TASK,
    "lines": {
        "apt": $APT_LINE,
        "copy_req": $COPY_REQ_LINE,
        "pip": $PIP_LINE,
        "copy_src": $COPY_SRC_LINE
    },
    "dockerignore": {
        "exists": $DOCKERIGNORE_EXISTS,
        "ignores_git": $IGNORES_GIT,
        "ignores_pycache": $IGNORES_PYCACHE
    },
    "image": {
        "exists": $IMAGE_EXISTS,
        "has_pip_layer": $HAS_PIP_LAYER,
        "has_apt_layer": $HAS_APT_LAYER
    },
    "functionality": {
        "container_works": $CONTAINER_WORKS
    }
}
EOF

# Fix permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"