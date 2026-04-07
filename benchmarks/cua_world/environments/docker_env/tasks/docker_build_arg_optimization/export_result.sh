#!/bin/bash
# Export script for docker_build_arg_optimization task
# This script performs the VALIDATION of the Dockerfile by running two builds
# and comparing the layer hashes to verify cache usage.

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_end_screenshot.png
fi

PROJECT_DIR="/home/ga/projects/version-app"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_MD5=$(cat /tmp/initial_dockerfile_md5 2>/dev/null || echo "0")

# 1. Check if Dockerfile was modified
CURRENT_MD5=$(md5sum "$PROJECT_DIR/Dockerfile" 2>/dev/null | awk '{print $1}' || echo "1")
DOCKERFILE_MODIFIED="false"
if [ "$CURRENT_MD5" != "$INITIAL_MD5" ]; then
    DOCKERFILE_MODIFIED="true"
fi

# 2. Verification Build Process
# We will build the image TWICE with different build args to verify caching.
# We do this as root/admin to ensure we control the daemon state for this check.

echo "Running Verification Build 1 (Version 1.0)..."
# Force DOCKER_BUILDKIT=1 for better introspection, though classic builder also works
export DOCKER_BUILDKIT=0 
# Note: Using legacy builder (DOCKER_BUILDKIT=0) makes it easier to inspect layer IDs 
# via `docker history` for this specific educational task logic.

# Build 1
docker build -t verify-app:v1 --build-arg APP_VERSION=1.0 "$PROJECT_DIR" > /tmp/build_v1.log 2>&1

# Extract Layer ID for 'pip install' from Build 1
# We look for the layer that executes pip install
LAYER_ID_V1=$(docker history --no-trunc verify-app:v1 | grep "pip install" | awk '{print $1}')

# Verify Functional Requirement (Version Persistence)
docker rm -f verify-test 2>/dev/null || true
docker run -d --name verify-test -p 5001:5000 verify-app:v1
sleep 3
RESPONSE_V1=$(curl -s http://localhost:5001/)
docker rm -f verify-test 2>/dev/null || true

# Parse response
VERSION_REPORTED_CORRECTLY="false"
if [[ "$RESPONSE_V1" == *"Version: 1.0"* ]]; then
    VERSION_REPORTED_CORRECTLY="true"
fi

echo "Running Verification Build 2 (Version 2.0)..."
# Build 2
docker build -t verify-app:v2 --build-arg APP_VERSION=2.0 "$PROJECT_DIR" > /tmp/build_v2.log 2>&1

# Extract Layer ID for 'pip install' from Build 2
LAYER_ID_V2=$(docker history --no-trunc verify-app:v2 | grep "pip install" | awk '{print $1}')

# 3. Analyze Cache Optimization
# If the Dockerfile is optimized, the 'pip install' layer should be indentical
# between v1 and v2 because the ARG change happened AFTER or didn't affect the input to RUN.
# Wait - if ARG is AFTER pip install, the history line for pip install is identical.
# If ARG is BEFORE pip install, the history line (and hash) changes because the build env changed.

CACHE_OPTIMIZED="false"
if [ -n "$LAYER_ID_V1" ] && [ -n "$LAYER_ID_V2" ]; then
    if [ "$LAYER_ID_V1" == "$LAYER_ID_V2" ]; then
        CACHE_OPTIMIZED="true"
    fi
fi

echo "Layer ID V1: $LAYER_ID_V1"
echo "Layer ID V2: $LAYER_ID_V2"
echo "Cache Optimized: $CACHE_OPTIMIZED"

# 4. Check for ENV instruction presence
HAS_ENV_INSTRUCTION="false"
if grep -q "ENV APP_VERSION" "$PROJECT_DIR/Dockerfile"; then
    HAS_ENV_INSTRUCTION="true"
fi

# 5. Export JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "dockerfile_modified": $DOCKERFILE_MODIFIED,
    "version_reported_correctly": $VERSION_REPORTED_CORRECTLY,
    "response_output": "$RESPONSE_V1",
    "cache_optimized": $CACHE_OPTIMIZED,
    "layer_id_v1": "$LAYER_ID_V1",
    "layer_id_v2": "$LAYER_ID_V2",
    "has_env_instruction": $HAS_ENV_INSTRUCTION
}
EOF

echo "Result JSON:"
cat /tmp/task_result.json