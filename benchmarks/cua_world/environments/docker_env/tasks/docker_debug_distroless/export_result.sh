#!/bin/bash
# Export script for docker_debug_distroless

echo "=== Exporting Distroless Debug Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Desktop/blackbox_report.json"
GROUND_TRUTH_PATH="/root/blackbox_ground_truth.json"

# 1. Check if report exists
REPORT_EXISTS=0
REPORT_VALID_JSON=0
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=1
    # Check if valid JSON
    if jq . "$REPORT_PATH" >/dev/null 2>&1; then
        REPORT_VALID_JSON=1
    fi
fi

# 2. Read Reported Values
REPORTED_PORT=0
REPORTED_TOKEN=""
if [ "$REPORT_VALID_JSON" = "1" ]; then
    REPORTED_PORT=$(jq -r '.port // 0' "$REPORT_PATH")
    REPORTED_TOKEN=$(jq -r '.auth_token // ""' "$REPORT_PATH")
fi

# 3. Read Ground Truth (requires root)
ACTUAL_PORT=$(jq -r '.port' "$GROUND_TRUTH_PATH")
ACTUAL_TOKEN=$(jq -r '.auth_token' "$GROUND_TRUTH_PATH")

# 4. Check Container State
CONTAINER_RUNNING=0
if docker ps | grep -q acme-blackbox; then
    CONTAINER_RUNNING=1
fi

# 5. Check Sidecar Usage (Trajectory Evidence)
# We check if any OTHER container was started with pid mode pointing to blackbox
# This is a heuristic; if the agent cleaned up, we might miss it, but standard
# 'docker run --rm' leaves trace in events if we captured them, but here we scan inspect.
# We'll just check if they got the right answer, which implies correct method.
# But we can check if they pulled/used a debug image like alpine or busybox.
DEBUG_IMAGE_USED=0
if docker images | grep -E "alpine|busybox|nicolaka/netshoot" > /dev/null; then
    DEBUG_IMAGE_USED=1
fi

# 6. Create Result JSON
cat > /tmp/distroless_result.json <<EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_valid_json": $REPORT_VALID_JSON,
    "reported_port": $REPORTED_PORT,
    "reported_token": "$REPORTED_TOKEN",
    "actual_port": $ACTUAL_PORT,
    "actual_token": "$ACTUAL_TOKEN",
    "container_running": $CONTAINER_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Results exported to /tmp/distroless_result.json"
cat /tmp/distroless_result.json
echo "=== Export Complete ==="