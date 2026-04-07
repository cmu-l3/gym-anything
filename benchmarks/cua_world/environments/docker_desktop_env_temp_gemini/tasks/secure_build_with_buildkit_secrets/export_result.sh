#!/bin/bash
# Export script for secure_build_with_buildkit_secrets

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

IMAGE_NAME="secure-app:latest"
TOKEN=$(cat /tmp/secret_token.txt)
RESULT_FILE="/tmp/task_result.json"

# Initialize variables
IMAGE_EXISTS="false"
ARTIFACT_FOUND="false"
TOKEN_IN_HISTORY="false"
TOKEN_IN_ENV="false"
USED_SECRET_MOUNT="false"

# 1. Check if image exists
if docker inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    IMAGE_EXISTS="true"
    echo "Image $IMAGE_NAME found."
else
    echo "Image $IMAGE_NAME NOT found."
fi

if [ "$IMAGE_EXISTS" = "true" ]; then
    # 2. Check for Artifact inside image
    # We use a temporary container to check file existence
    echo "Checking for artifact..."
    if docker run --rm "$IMAGE_NAME" test -f /app/proprietary_lib.tar.gz; then
        ARTIFACT_FOUND="true"
        echo "Artifact found in image."
    else
        echo "Artifact missing in image."
    fi

    # 3. Check for Token in History (The primary security check)
    # docker history prints the commands. We grep for the token.
    echo "Checking build history for leaks..."
    HISTORY_OUTPUT=$(docker history --no-trunc "$IMAGE_NAME")
    if echo "$HISTORY_OUTPUT" | grep -q "$TOKEN"; then
        TOKEN_IN_HISTORY="true"
        echo "SECURITY FAIL: Token found in build history."
    else
        echo "History check passed."
    fi

    # 4. Check for Token in ENV/Config
    echo "Checking image config for leaks..."
    ENV_OUTPUT=$(docker inspect "$IMAGE_NAME" --format '{{json .Config.Env}}')
    if echo "$ENV_OUTPUT" | grep -q "$TOKEN"; then
        TOKEN_IN_ENV="true"
        echo "SECURITY FAIL: Token found in environment variables."
    else
        echo "Env check passed."
    fi
fi

# 5. Check Dockerfile for secret mount usage (Static analysis)
DOCKERFILE="/home/ga/secure-build/Dockerfile"
if [ -f "$DOCKERFILE" ]; then
    if grep -q "mount=type=secret" "$DOCKERFILE"; then
        USED_SECRET_MOUNT="true"
        echo "Dockerfile uses secret mount syntax."
    else
        echo "Dockerfile does NOT use secret mount syntax."
    fi
fi

# 6. Stop the background server
pkill -f "artifact_server.py" || true

# 7. Create JSON result
cat > "$RESULT_FILE" << EOF
{
    "image_exists": $IMAGE_EXISTS,
    "artifact_found": $ARTIFACT_FOUND,
    "token_leaked_in_history": $TOKEN_IN_HISTORY,
    "token_leaked_in_env": $TOKEN_IN_ENV,
    "dockerfile_uses_secret_mount": $USED_SECRET_MOUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Fix permissions
chmod 666 "$RESULT_FILE"

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="