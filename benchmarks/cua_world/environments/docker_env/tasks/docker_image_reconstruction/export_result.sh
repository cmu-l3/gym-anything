#!/bin/bash
echo "=== Exporting Docker Image Reconstruction Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper to inspect image config safely
inspect_val() {
    local img="$1"
    local path="$2"
    docker inspect "$img" --format "{{json $path}}" 2>/dev/null || echo "null"
}

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# 1. CHECK FILE EXISTENCE
# ------------------------------------------------------------------
API_DF_EXISTS=$([ -f "/home/ga/projects/acme-services/api/Dockerfile" ] && echo "true" || echo "false")
CRON_DF_EXISTS=$([ -f "/home/ga/projects/acme-services/cron/Dockerfile" ] && echo "true" || echo "false")
GW_DF_EXISTS=$([ -f "/home/ga/projects/acme-services/gateway/Dockerfile" ] && echo "true" || echo "false")
NOTES_EXISTS=$([ -f "/home/ga/Desktop/reconstruction_notes.txt" ] && echo "true" || echo "false")

# ------------------------------------------------------------------
# 2. CHECK IMAGE CONFIGURATIONS
# ------------------------------------------------------------------
# Check acme-api:reconstructed
API_IMG="acme-api:reconstructed"
API_EXISTS=$(docker images -q "$API_IMG" 2>/dev/null)
if [ -n "$API_EXISTS" ]; then
    API_USER=$(inspect_val "$API_IMG" .Config.User)
    API_WORKDIR=$(inspect_val "$API_IMG" .Config.WorkingDir)
    API_HEALTH=$(inspect_val "$API_IMG" .Config.Healthcheck)
    API_PORTS=$(inspect_val "$API_IMG" .Config.ExposedPorts)
else
    API_USER="null"; API_WORKDIR="null"; API_HEALTH="null"; API_PORTS="null"
fi

# Check acme-cron:reconstructed
CRON_IMG="acme-cron:reconstructed"
CRON_EXISTS=$(docker images -q "$CRON_IMG" 2>/dev/null)
if [ -n "$CRON_EXISTS" ]; then
    CRON_ENV=$(inspect_val "$CRON_IMG" .Config.Env)
    CRON_ENTRY=$(inspect_val "$CRON_IMG" .Config.Entrypoint)
    CRON_CMD=$(inspect_val "$CRON_IMG" .Config.Cmd)
    CRON_WORKDIR=$(inspect_val "$CRON_IMG" .Config.WorkingDir)
else
    CRON_ENV="null"; CRON_ENTRY="null"; CRON_CMD="null"; CRON_WORKDIR="null"
fi

# Check acme-gateway:reconstructed
GW_IMG="acme-gateway:reconstructed"
GW_EXISTS=$(docker images -q "$GW_IMG" 2>/dev/null)
if [ -n "$GW_EXISTS" ]; then
    GW_PORTS=$(inspect_val "$GW_IMG" .Config.ExposedPorts)
else
    GW_PORTS="null"
fi

# ------------------------------------------------------------------
# 3. FUNCTIONAL TESTS
# ------------------------------------------------------------------
echo "Running functional tests..."

# Test API
API_FUNCTIONAL="false"
if [ -n "$API_EXISTS" ]; then
    docker rm -f test-api 2>/dev/null || true
    docker run -d --name test-api -p 5050:5000 "$API_IMG" >/dev/null 2>&1
    sleep 5
    if curl -s -f http://localhost:5050/health >/dev/null; then
        API_FUNCTIONAL="true"
    fi
    docker rm -f test-api >/dev/null 2>&1 || true
fi

# Test Gateway
GW_FUNCTIONAL="false"
if [ -n "$GW_EXISTS" ]; then
    docker rm -f test-gw 2>/dev/null || true
    docker run -d --name test-gw -p 8080:80 "$GW_IMG" >/dev/null 2>&1
    sleep 3
    if nc -z localhost 8080; then
        GW_FUNCTIONAL="true"
    fi
    docker rm -f test-gw >/dev/null 2>&1 || true
fi

# Test Cron
CRON_FUNCTIONAL="false"
if [ -n "$CRON_EXISTS" ]; then
    docker rm -f test-cron 2>/dev/null || true
    docker run -d --name test-cron "$CRON_IMG" >/dev/null 2>&1
    sleep 5
    if [ "$(docker inspect -f '{{.State.Running}}' test-cron 2>/dev/null)" == "true" ]; then
        CRON_FUNCTIONAL="true"
    fi
    docker rm -f test-cron >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------
# 4. EXPORT JSON
# ------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "files": {
        "api_dockerfile": $API_DF_EXISTS,
        "cron_dockerfile": $CRON_DF_EXISTS,
        "gateway_dockerfile": $GW_DF_EXISTS,
        "notes": $NOTES_EXISTS
    },
    "images_exist": {
        "api": $([ -n "$API_EXISTS" ] && echo "true" || echo "false"),
        "cron": $([ -n "$CRON_EXISTS" ] && echo "true" || echo "false"),
        "gateway": $([ -n "$GW_EXISTS" ] && echo "true" || echo "false")
    },
    "configs": {
        "api": {
            "User": $API_USER,
            "WorkingDir": $API_WORKDIR,
            "Healthcheck": $API_HEALTH,
            "ExposedPorts": $API_PORTS
        },
        "cron": {
            "Env": $CRON_ENV,
            "Entrypoint": $CRON_ENTRY,
            "Cmd": $CRON_CMD,
            "WorkingDir": $CRON_WORKDIR
        },
        "gateway": {
            "ExposedPorts": $GW_PORTS
        }
    },
    "functional": {
        "api": $API_FUNCTIONAL,
        "cron": $CRON_FUNCTIONAL,
        "gateway": $GW_FUNCTIONAL
    }
}
EOF

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="