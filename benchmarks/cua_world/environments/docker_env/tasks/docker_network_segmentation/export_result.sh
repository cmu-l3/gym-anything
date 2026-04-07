#!/bin/bash
echo "=== Exporting Network Segmentation Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/projects/acme-platform"

# 1. Network Existence Check
NET_DMZ=$(docker network ls --format '{{.Name}}' | grep -x "dmz-net" || echo "")
NET_APP=$(docker network ls --format '{{.Name}}' | grep -x "app-net" || echo "")
NET_DATA=$(docker network ls --format '{{.Name}}' | grep -x "data-net" || echo "")
NET_FLAT=$(docker network ls --format '{{.Name}}' | grep -x "acme-flat" || echo "")

# 2. Container Network Membership
# We use a python one-liner to parse 'docker inspect' output accurately
INSPECT_JSON=$(docker inspect acme-proxy acme-api acme-users acme-orders acme-db acme-cache 2>/dev/null || echo "[]")

# 3. Connectivity / Isolation Checks (The "Proof")
# We use 'timeout 2 nc -z <host> <port>' to test TCP reachability

# Isolation: Proxy -> DB (Should FAIL)
ISO_PROXY_DB="fail"
if docker exec acme-proxy timeout 2 nc -z acme-db 5432 2>/dev/null; then
    ISO_PROXY_DB="connected" # Bad
else
    ISO_PROXY_DB="isolated"  # Good
fi

# Isolation: Proxy -> Cache (Should FAIL)
ISO_PROXY_CACHE="fail"
if docker exec acme-proxy timeout 2 nc -z acme-cache 6379 2>/dev/null; then
    ISO_PROXY_CACHE="connected" # Bad
else
    ISO_PROXY_CACHE="isolated"  # Good
fi

# Connectivity: Proxy -> API (Should SUCCEED)
CON_PROXY_API="fail"
if docker exec acme-proxy timeout 2 nc -z acme-api 5000 2>/dev/null; then
    CON_PROXY_API="connected"
fi

# Connectivity: Users -> DB (Should SUCCEED)
CON_USERS_DB="fail"
if docker exec acme-users timeout 2 nc -z acme-db 5432 2>/dev/null; then
    CON_USERS_DB="connected"
fi

# End-to-End: Localhost -> Proxy -> API
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>/dev/null || echo "000")

# 4. Architecture Document
DOC_PATH="/home/ga/Desktop/network_architecture.txt"
DOC_EXISTS="false"
DOC_CONTENT=""
if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_CONTENT=$(cat "$DOC_PATH" | base64 -w 0)
    DOC_MTIME=$(stat -c %Y "$DOC_PATH")
fi

# 5. Running Status
RUNNING_COUNT=$(docker ps --format '{{.Names}}' | grep -c "acme-")

# Export to JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "networks": {
        "dmz_net": "$NET_DMZ",
        "app_net": "$NET_APP",
        "data_net": "$NET_DATA",
        "acme_flat": "$NET_FLAT"
    },
    "inspect_data": $INSPECT_JSON,
    "connectivity": {
        "isolation_proxy_db": "$ISO_PROXY_DB",
        "isolation_proxy_cache": "$ISO_PROXY_CACHE",
        "conn_proxy_api": "$CON_PROXY_API",
        "conn_users_db": "$CON_USERS_DB",
        "http_status": "$HTTP_STATUS"
    },
    "documentation": {
        "exists": $DOC_EXISTS,
        "content_b64": "$DOC_CONTENT",
        "mtime": "${DOC_MTIME:-0}"
    },
    "running_count": $RUNNING_COUNT
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete."