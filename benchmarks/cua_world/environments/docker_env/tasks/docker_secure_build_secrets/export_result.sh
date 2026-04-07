#!/bin/bash
# Export script for docker_secure_build_secrets task

echo "=== Exporting Docker Secure Build Secrets Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/projects/acme-trading-bot"
IMAGE_TAG="acme-trading-bot:secure"
TOKEN_VALUE="acme_prod_8x92_secure_token_v1"

# 1. Verify Image Existence
IMAGE_EXISTS=0
if docker inspect "$IMAGE_TAG" > /dev/null 2>&1; then
    IMAGE_EXISTS=1
fi

# 2. Check for Token Leak in History (CRITICAL)
# docker history --no-trunc shows the full command. If the token is there, it failed.
HISTORY_LEAK=0
if [ "$IMAGE_EXISTS" = "1" ]; then
    if docker history --no-trunc "$IMAGE_TAG" 2>&1 | grep -q "$TOKEN_VALUE"; then
        HISTORY_LEAK=1
    fi
fi

# 3. Check for Successful Build (Lockfile existence)
# Does the image actually contain the proof that install_deps ran with the correct token?
BUILD_SUCCESS=0
if [ "$IMAGE_EXISTS" = "1" ]; then
    if docker run --rm --entrypoint="" "$IMAGE_TAG" cat /app/deps_installed.lock > /dev/null 2>&1; then
        BUILD_SUCCESS=1
    fi
fi

# 4. Analyze Implementation Details (Static Analysis)

# Check Dockerfile for mount usage
DOCKERFILE_USES_MOUNT=0
if grep -q "\-\-mount=type=secret" "$PROJECT_DIR/Dockerfile"; then
    DOCKERFILE_USES_MOUNT=1
fi

# Check Dockerfile for ARG removal (optional but good practice)
DOCKERFILE_HAS_ARG=0
if grep -q "ARG ARTIFACTORY_TOKEN" "$PROJECT_DIR/Dockerfile"; then
    DOCKERFILE_HAS_ARG=1
fi

# Check install_deps.sh for reading from secret path
SCRIPT_READS_SECRET=0
if grep -q "/run/secrets/" "$PROJECT_DIR/install_deps.sh"; then
    SCRIPT_READS_SECRET=1
fi

# Check build.sh for --secret usage
BUILD_SCRIPT_USES_SECRET=0
if grep -q "\-\-secret" "$PROJECT_DIR/build.sh"; then
    BUILD_SCRIPT_USES_SECRET=1
fi

# 5. Check if build.sh was actually modified/used
BUILD_SCRIPT_MODIFIED=0
if [ -f "$PROJECT_DIR/build.sh" ]; then
    MTIME=$(stat -c %Y "$PROJECT_DIR/build.sh")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        BUILD_SCRIPT_MODIFIED=1
    fi
fi

# 6. Capture Image ID to ensure it's not the old one (though History check covers this)
IMAGE_ID=$(docker inspect --format="{{.Id}}" "$IMAGE_TAG" 2>/dev/null || echo "")

cat > /tmp/task_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "image_exists": $IMAGE_EXISTS,
    "history_leak": $HISTORY_LEAK,
    "build_success": $BUILD_SUCCESS,
    "dockerfile_uses_mount": $DOCKERFILE_USES_MOUNT,
    "dockerfile_has_arg": $DOCKERFILE_HAS_ARG,
    "script_reads_secret": $SCRIPT_READS_SECRET,
    "build_script_uses_secret": $BUILD_SCRIPT_USES_SECRET,
    "build_script_modified": $BUILD_SCRIPT_MODIFIED,
    "image_id": "$IMAGE_ID",
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="