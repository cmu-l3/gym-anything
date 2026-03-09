#!/bin/bash
echo "=== Exporting Sidecar Packet Capture Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

PROJECT_DIR="/home/ga/debug-auth"
PCAP_FILE="$PROJECT_DIR/captures/capture.pcap"

# 1. Check if PCAP file exists and get size
PCAP_EXISTS="false"
PCAP_SIZE="0"
if [ -f "$PCAP_FILE" ]; then
    PCAP_EXISTS="true"
    PCAP_SIZE=$(stat -c %s "$PCAP_FILE" 2>/dev/null || echo "0")
fi

# 2. Inspect Sniffer Container
# We look for a container named 'sniffer' OR a service named 'sniffer'
SNIFFER_ID=$(docker ps -q --filter "name=sniffer" | head -1)
if [ -z "$SNIFFER_ID" ]; then
    # Try finding by compose service label
    SNIFFER_ID=$(docker ps -q --filter "label=com.docker.compose.service=sniffer" | head -1)
fi

SNIFFER_FOUND="false"
IS_RUNNING="false"
IS_PRIVILEGED="false"
CAP_ADD="[]"
NETWORK_MODE=""
IMAGE=""

if [ -n "$SNIFFER_ID" ]; then
    SNIFFER_FOUND="true"
    INSPECT_JSON=$(docker inspect "$SNIFFER_ID")
    
    # Check status
    STATUS=$(echo "$INSPECT_JSON" | grep -Po '"Status": "\K.*?(?=")')
    if [ "$STATUS" == "running" ]; then
        IS_RUNNING="true"
    fi

    # Check Privileged
    if echo "$INSPECT_JSON" | grep -q '"Privileged": true'; then
        IS_PRIVILEGED="true"
    fi

    # Get Capabilities using python for reliable parsing
    CAP_ADD=$(echo "$INSPECT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)[0]['HostConfig'].get('CapAdd', []))" 2>/dev/null || echo "[]")

    # Get Network Mode
    NETWORK_MODE=$(echo "$INSPECT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)[0]['HostConfig'].get('NetworkMode', ''))" 2>/dev/null || echo "")

    # Get Image
    IMAGE=$(echo "$INSPECT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)[0]['Config']['Image'])" 2>/dev/null || echo "")
fi

# 3. Get Auth Service ID for network comparison
AUTH_ID=$(docker ps -q --filter "name=auth-service" | head -1)
if [ -z "$AUTH_ID" ]; then
    AUTH_ID=$(docker ps -q --filter "label=com.docker.compose.service=auth-service" | head -1)
fi

# 4. Check if docker-compose.yml was modified
COMPOSE_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
COMPOSE_MTIME=$(stat -c %Y "$PROJECT_DIR/docker-compose.yml" 2>/dev/null || echo "0")
if [ "$COMPOSE_MTIME" -gt "$TASK_START" ]; then
    COMPOSE_MODIFIED="true"
fi

# 5. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "pcap_exists": $PCAP_EXISTS,
    "pcap_size": $PCAP_SIZE,
    "sniffer_found": $SNIFFER_FOUND,
    "is_running": $IS_RUNNING,
    "is_privileged": $IS_PRIVILEGED,
    "cap_add": $(echo "$CAP_ADD" | sed "s/'/\"/g"), 
    "network_mode": "$NETWORK_MODE",
    "auth_container_id": "$AUTH_ID",
    "sniffer_image": "$IMAGE",
    "compose_modified": $COMPOSE_MODIFIED
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json