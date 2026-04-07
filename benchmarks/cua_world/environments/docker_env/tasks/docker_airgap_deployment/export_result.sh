#!/bin/bash
echo "=== Exporting Air-Gapped Deployment Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_final.png
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REMOTE_HOST="tcp://localhost:2375"

# 1. check local build
LOCAL_IMAGE_EXISTS="false"
if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "inventory-tracker:v1"; then
    LOCAL_IMAGE_EXISTS="true"
fi

# 2. Check remote image existence
REMOTE_IMAGE_EXISTS="false"
if docker -H "$REMOTE_HOST" images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "inventory-tracker:v1"; then
    REMOTE_IMAGE_EXISTS="true"
fi

# 3. Check remote container status
REMOTE_CONTAINER_RUNNING="false"
REMOTE_CONTAINER_NAME=""
# We look for tracker-app specifically, but also accept any container running the image
CONTAINER_ID=$(docker -H "$REMOTE_HOST" ps -q --filter "ancestor=inventory-tracker:v1" 2>/dev/null | head -n 1)

if [ -n "$CONTAINER_ID" ]; then
    REMOTE_CONTAINER_RUNNING="true"
    REMOTE_CONTAINER_NAME=$(docker -H "$REMOTE_HOST" inspect --format '{{.Name}}' "$CONTAINER_ID" | sed 's/\///')
    
    # Check restart policy
    RESTART_POLICY=$(docker -H "$REMOTE_HOST" inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER_ID")
    
    # Check port mapping (HostPort 8080 -> ContainerPort 5000)
    # Note: This checks the mapping inside the dind container
    PORT_MAP=$(docker -H "$REMOTE_HOST" inspect --format '{{(index (index .NetworkSettings.Ports "5000/tcp") 0).HostPort}}' "$CONTAINER_ID" 2>/dev/null || echo "none")
else
    RESTART_POLICY="none"
    PORT_MAP="none"
fi

# 4. Functional Check
APP_RESPONDING="false"
APP_RESPONSE=""
# Attempt to curl localhost:8080 (which maps to dind:8080, which maps to container:5000)
if curl -s --max-time 5 http://localhost:8080/ > /tmp/app_response.json; then
    if grep -q "Inventory Tracker" /tmp/app_response.json; then
        APP_RESPONDING="true"
        APP_RESPONSE=$(cat /tmp/app_response.json)
    fi
fi

# 5. Check isolation (Verify prod-secure is still internal only)
ISOLATION_MAINTAINED="false"
NETWORK_INTERNAL=$(docker network inspect secure-net --format '{{.Internal}}' 2>/dev/null)
if [ "$NETWORK_INTERNAL" = "true" ]; then
    ISOLATION_MAINTAINED="true"
fi

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "local_image_exists": $LOCAL_IMAGE_EXISTS,
    "remote_image_exists": $REMOTE_IMAGE_EXISTS,
    "remote_container_running": $REMOTE_CONTAINER_RUNNING,
    "remote_container_name": "$REMOTE_CONTAINER_NAME",
    "restart_policy": "$RESTART_POLICY",
    "port_mapping": "$PORT_MAP",
    "app_responding": $APP_RESPONDING,
    "isolation_maintained": $ISOLATION_MAINTAINED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="