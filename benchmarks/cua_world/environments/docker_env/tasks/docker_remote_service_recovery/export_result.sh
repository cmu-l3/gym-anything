#!/bin/bash
echo "=== Exporting Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Timestamp for verification
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check if the 'staging' context exists on the AGENT machine (local)
# We run as 'ga' because contexts are user-specific
CONTEXT_EXISTS=$(su - ga -c "docker context inspect staging 2>/dev/null" >/dev/null && echo "true" || echo "false")
CONTEXT_ENDPOINT=$(su - ga -c "docker context inspect staging --format '{{.Endpoints.docker.Host}}' 2>/dev/null" || echo "")

# 2. Check the Remote Host state (staging-node)
# We use a temporary container or direct -H to query the DinD container
# Since we are root in export_result (usually), and we have network access:
REMOTE_HOST="tcp://staging-node:2375"

# Helper to run docker command against remote host using the docker cli container or direct if available
# We'll use the docker binary present in the environment, assuming it can reach the network
# (The environment container is connected to staging-net)

# Check if web-proxy exists and is running on REMOTE
REMOTE_CONTAINER_INFO=$(docker -H "$REMOTE_HOST" inspect web-proxy 2>/dev/null || echo "{}")

# Extract details if container exists
CONTAINER_EXISTS="false"
IS_RUNNING="false"
ENV_VAR_SET="false"
PORT_MAPPED="false"
IMAGE_CORRECT="false"

if [ "$REMOTE_CONTAINER_INFO" != "{}" ] && [ "$REMOTE_CONTAINER_INFO" != "[]" ]; then
    CONTAINER_EXISTS="true"
    
    # Check Status
    STATUS=$(echo "$REMOTE_CONTAINER_INFO" | grep -o '"Status": "[^"]*"' | head -1 | cut -d'"' -f4)
    if [ "$STATUS" == "running" ]; then
        IS_RUNNING="true"
    fi

    # Check Env Var (UPSTREAM_TARGET)
    if echo "$REMOTE_CONTAINER_INFO" | grep -q "UPSTREAM_TARGET="; then
        ENV_VAR_SET="true"
    fi

    # Check Port Mapping (8080->80)
    # The JSON structure for ports is complex, simplistic grep check for evidence
    if echo "$REMOTE_CONTAINER_INFO" | grep -q '"HostPort": "8080"' && echo "$REMOTE_CONTAINER_INFO" | grep -q '"80/tcp"'; then
        PORT_MAPPED="true"
    fi

    # Check Image
    IMAGE=$(echo "$REMOTE_CONTAINER_INFO" | grep -o '"Image": "[^"]*"' | head -1 | cut -d'"' -f4)
    # The inspect might return sha256 or name. We check Config.Image usually
    CONFIG_IMAGE=$(docker -H "$REMOTE_HOST" inspect web-proxy --format '{{.Config.Image}}' 2>/dev/null)
    if [[ "$CONFIG_IMAGE" == *"nginx:alpine"* ]]; then
        IMAGE_CORRECT="true"
    fi
fi

# 3. Check anti-gaming: Ensure the container is NOT running locally
LOCAL_CONTAINER_RUNNING=$(docker inspect web-proxy --format '{{.State.Running}}' 2>/dev/null || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "context_exists": $CONTEXT_EXISTS,
    "context_endpoint": "$CONTEXT_ENDPOINT",
    "remote_container_exists": $CONTAINER_EXISTS,
    "remote_container_running": $IS_RUNNING,
    "env_var_set": $ENV_VAR_SET,
    "port_mapped": $PORT_MAPPED,
    "image_correct": $IMAGE_CORRECT,
    "local_container_running": $LOCAL_CONTAINER_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="