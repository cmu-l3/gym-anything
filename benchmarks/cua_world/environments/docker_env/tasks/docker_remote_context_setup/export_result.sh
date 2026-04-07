#!/bin/bash
echo "=== Exporting Docker Remote Context Result ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot /tmp/task_final.png

# Load expected data
REMOTE_IP=$(cat /tmp/remote_ip.txt 2>/dev/null || echo "0.0.0.0")

# 1. Check Context Existence
CONTEXT_EXISTS="false"
CONTEXT_JSON=""
if docker context inspect prod > /dev/null 2>&1; then
    CONTEXT_EXISTS="true"
    CONTEXT_JSON=$(docker context inspect prod)
fi

# 2. Check Context Configuration (Endpoints & TLS)
# We parse the json to verify it points to tcp://<IP>:2376 or tcp://prod-node:2376
HOST_URL=""
CA_PATH=""
CERT_PATH=""
KEY_PATH=""
SKIP_TLS_VERIFY=""

if [ "$CONTEXT_EXISTS" = "true" ]; then
    HOST_URL=$(echo "$CONTEXT_JSON" | grep -o '"Host": *"[^"]*"' | cut -d'"' -f4)
    SKIP_TLS_VERIFY=$(echo "$CONTEXT_JSON" | grep -o '"SkipTLSVerify": *[^,]*' | cut -d':' -f2 | tr -d ' ,')
    
    # Paths might be absolute
    CA_PATH=$(echo "$CONTEXT_JSON" | grep -o '"CaPath": *"[^"]*"' | cut -d'"' -f4)
    CERT_PATH=$(echo "$CONTEXT_JSON" | grep -o '"CertPath": *"[^"]*"' | cut -d'"' -f4)
    KEY_PATH=$(echo "$CONTEXT_JSON" | grep -o '"KeyPath": *"[^"]*"' | cut -d'"' -f4)
fi

# 3. Functional Connection Test
# Can we list containers on the remote node using the AGENT'S context?
CONNECTION_SUCCESS="false"
if [ "$CONTEXT_EXISTS" = "true" ]; then
    if docker --context prod info > /dev/null 2>&1; then
        CONNECTION_SUCCESS="true"
    fi
fi

# 4. Workload Verification
# Check if 'prod-web' is running on the REMOTE node
REMOTE_WORKLOAD_RUNNING="false"
if docker exec prod-node docker ps --format '{{.Names}}' 2>/dev/null | grep -q "prod-web"; then
    REMOTE_WORKLOAD_RUNNING="true"
fi

# 5. Anti-Gaming Check
# Check if 'prod-web' is running on the LOCAL node
LOCAL_WORKLOAD_RUNNING="false"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "prod-web"; then
    LOCAL_WORKLOAD_RUNNING="true"
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "context_exists": $CONTEXT_EXISTS,
    "host_url": "$HOST_URL",
    "remote_ip_expected": "$REMOTE_IP",
    "ca_path": "$CA_PATH",
    "cert_path": "$CERT_PATH",
    "key_path": "$KEY_PATH",
    "skip_tls_verify": "$SKIP_TLS_VERIFY",
    "connection_success": $CONNECTION_SUCCESS,
    "remote_workload_running": $REMOTE_WORKLOAD_RUNNING,
    "local_workload_running": $LOCAL_WORKLOAD_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="