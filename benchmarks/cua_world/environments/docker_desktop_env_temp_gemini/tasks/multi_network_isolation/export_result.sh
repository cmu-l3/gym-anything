#!/bin/bash
# Export script for multi_network_isolation task

echo "=== Exporting multi_network_isolation result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper function to get JSON info for a container
inspect_container() {
    local name=$1
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        docker inspect "$name" 2>/dev/null
    else
        echo "null"
    fi
}

# Helper function to inspect a network
inspect_network() {
    local name=$1
    if docker network ls --format '{{.Name}}' | grep -q "^${name}$"; then
        docker network inspect "$name" 2>/dev/null
    else
        echo "null"
    fi
}

# Collect data
echo "Collecting container and network data..."

# Containers
WEB_PROXY_JSON=$(inspect_container "web-proxy")
APP_SERVER_JSON=$(inspect_container "app-server")
DATA_STORE_JSON=$(inspect_container "data-store")

# Networks
FRONTEND_NET_JSON=$(inspect_network "frontend")
BACKEND_NET_JSON=$(inspect_network "backend")

# Create comprehensive result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "containers": {
        "web_proxy": $WEB_PROXY_JSON,
        "app_server": $APP_SERVER_JSON,
        "data_store": $DATA_STORE_JSON
    },
    "networks": {
        "frontend": $FRONTEND_NET_JSON,
        "backend": $BACKEND_NET_JSON
    },
    "docker_info": {
        "daemon_running": $(docker_daemon_ready && echo "true" || echo "false"),
        "desktop_running": $(docker_desktop_running && echo "true" || echo "false")
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="