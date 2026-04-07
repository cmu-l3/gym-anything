#!/bin/bash
# Export script for docker_entrypoint_debug

echo "=== Exporting Results ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check container status
check_container() {
    local name="$1"
    local running=0
    local uptime=0
    local restarts=0
    
    # Check if running
    if [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" == "true" ]; then
        running=1
        
        # Check uptime (started at)
        local start_ts=$(date -d "$(docker inspect -f '{{.State.StartedAt}}' "$name")" +%s)
        local now_ts=$(date +%s)
        uptime=$((now_ts - start_ts))
        
        # Check restart count
        restarts=$(docker inspect -f '{{.RestartCount}}' "$name" 2>/dev/null)
    fi
    
    echo "$running,$uptime,$restarts"
}

# 2. Check functional health
check_health() {
    local service="$1"
    local status="failed"
    
    case $service in
        "acme-cache-warmer")
            # Check logs for success message
            if docker logs acme-cache-warmer 2>&1 | grep -q "Mode: fast"; then
                status="healthy"
            fi
            ;;
        "acme-event-processor")
            # Check logs for node output
            if docker logs acme-event-processor 2>&1 | grep -q "Event processor worker started"; then
                status="healthy"
            fi
            ;;
        "acme-report-generator")
            # Curl endpoint
            if curl -s http://localhost:8000 2>/dev/null | grep -q "Report Generator Healthy"; then
                status="healthy"
            fi
            ;;
        "acme-static-server")
            # Curl endpoint
            if curl -s http://localhost:8080 2>/dev/null | grep -q "Acme Static Server"; then
                status="healthy"
            fi
            ;;
    esac
    echo "$status"
}

# 3. Check if images were rebuilt
check_rebuild() {
    local image="$1"
    local created_ts=$(date -d "$(docker inspect -f '{{.Created}}' "$image" 2>/dev/null)" +%s 2>/dev/null || echo "0")
    if [ "$created_ts" -gt "$TASK_START" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Collect data
IFS=',' read R1 U1 RS1 <<< $(check_container "acme-cache-warmer")
IFS=',' read R2 U2 RS2 <<< $(check_container "acme-event-processor")
IFS=',' read R3 U3 RS3 <<< $(check_container "acme-report-generator")
IFS=',' read R4 U4 RS4 <<< $(check_container "acme-static-server")

H1=$(check_health "acme-cache-warmer")
H2=$(check_health "acme-event-processor")
H3=$(check_health "acme-report-generator")
H4=$(check_health "acme-static-server")

IMG1_REBUILT=$(check_rebuild "acme-cache-warmer:latest")
IMG2_REBUILT=$(check_rebuild "acme-event-processor:latest")
IMG3_REBUILT=$(check_rebuild "acme-report-generator:latest")
IMG4_REBUILT=$(check_rebuild "acme-static-server:latest")

# 4. Check Report
REPORT_PATH="/home/ga/Desktop/debugging_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # Capture snippet for VLM/logging
fi

# 5. Check cleanup (Original broken containers not crashing)
# Logic: If we see high restart counts on *running* containers, it's bad.
# Or if we see stopped containers with recent exit codes.
# Actually, the user should have replaced them. The `check_container` logic covers the new ones.
# We will just verify the current named containers are stable.

# Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Generate JSON
cat > /tmp/task_result.json << EOF
{
  "task_start_time": $TASK_START,
  "services": {
    "acme-cache-warmer": {
      "running": $R1,
      "uptime": $U1,
      "restarts": $RS1,
      "health": "$H1",
      "rebuilt": $IMG1_REBUILT
    },
    "acme-event-processor": {
      "running": $R2,
      "uptime": $U2,
      "restarts": $RS2,
      "health": "$H2",
      "rebuilt": $IMG2_REBUILT
    },
    "acme-report-generator": {
      "running": $R3,
      "uptime": $U3,
      "restarts": $RS3,
      "health": "$H3",
      "rebuilt": $IMG3_REBUILT
    },
    "acme-static-server": {
      "running": $R4,
      "uptime": $U4,
      "restarts": $RS4,
      "health": "$H4",
      "rebuilt": $IMG4_REBUILT
    }
  },
  "report": {
    "exists": $REPORT_EXISTS,
    "size": $REPORT_SIZE
  },
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json