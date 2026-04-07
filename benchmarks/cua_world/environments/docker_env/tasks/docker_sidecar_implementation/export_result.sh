#!/bin/bash
echo "=== Exporting Sidecar Implementation Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/projects/settlement-system"

# 1. Check which services are running
LEGACY_RUNNING=$(container_running_flag legacy-core)
# Agent might name them differently, so we check for functionality via docker ps
# But strict instructions said 'log-sidecar' and 'report-sidecar'
LOG_SIDECAR_RUNNING=0
REPORT_SIDECAR_RUNNING=0
docker ps --format '{{.Names}}' | grep -q "log-sidecar" && LOG_SIDECAR_RUNNING=1
docker ps --format '{{.Names}}' | grep -q "report-sidecar" && REPORT_SIDECAR_RUNNING=1

# 2. Inspect Volumes (Crucial)
# We need to verify that legacy-core SHARES volumes with the sidecars
LEGACY_MOUNTS=$(docker inspect legacy-core --format '{{json .Mounts}}' 2>/dev/null || echo "[]")

# 3. Verify Log Sidecar Functionality
# Does the log sidecar actually output the transaction logs?
LOG_CONTENT_DETECTED=0
if [ "$LOG_SIDECAR_RUNNING" = "1" ]; then
    # Grab last 20 lines of logs
    SIDECAR_LOGS=$(docker logs log-sidecar --tail 20 2>&1)
    if echo "$SIDECAR_LOGS" | grep -q "TXN_ID_"; then
        LOG_CONTENT_DETECTED=1
    fi
fi

# 4. Verify Report Sidecar Functionality
# Can we reach the report via HTTP?
REPORT_HTTP_STATUS=0
REPORT_CONTENT_VALID=0

if [ "$REPORT_SIDECAR_RUNNING" = "1" ]; then
    # Try fetching the report
    HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/latest.html || echo "000")
    if [ "$HTTP_RESPONSE" = "200" ]; then
        REPORT_HTTP_STATUS=1
        # Check content
        CONTENT=$(curl -s http://localhost:8080/latest.html)
        if echo "$CONTENT" | grep -q "Daily Settlement Report"; then
            REPORT_CONTENT_VALID=1
        fi
    fi
fi

# 5. Check configuration file for race condition handling
# We look for a robust command like "touch ... && tail" or a while loop
COMPOSE_CONTENT=""
if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    COMPOSE_CONTENT=$(cat "$PROJECT_DIR/docker-compose.yml")
fi

HAS_ROBUST_COMMAND=0
# Crude check for robustness: looking for logic that handles missing file or pre-creates it
# e.g., "touch", "while", "until", "sleep"
if echo "$COMPOSE_CONTENT" | grep -qE "touch|while|until|sleep"; then
    HAS_ROBUST_COMMAND=1
fi

# 6. Helper for container running check
container_running_flag() {
    local name="$1"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
        echo 1
    else
        echo 0
    fi
}

# 7. Generate Result JSON
cat > /tmp/sidecar_result.json <<EOF
{
  "task_start": ${TASK_START},
  "legacy_running": $(container_running_flag legacy-core),
  "log_sidecar_running": ${LOG_SIDECAR_RUNNING},
  "report_sidecar_running": ${REPORT_SIDECAR_RUNNING},
  "log_content_detected": ${LOG_CONTENT_DETECTED},
  "report_http_accessible": ${REPORT_HTTP_STATUS},
  "report_content_valid": ${REPORT_CONTENT_VALID},
  "has_robust_command": ${HAS_ROBUST_COMMAND},
  "legacy_mounts": ${LEGACY_MOUNTS},
  "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON written to /tmp/sidecar_result.json"
cat /tmp/sidecar_result.json
echo "=== Export Complete ==="