#!/bin/bash
echo "=== Exporting Signal Handling Results ==="
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
EXPORT_TIMESTAMP=$(date +%s)
take_screenshot /tmp/task_final.png

# ── Function to measure stop time ────────────────────────────────────────────
measure_stop_time() {
    local container=$1
    local timeout_sec=5
    
    # Check if running
    if ! docker ps -q --filter "name=^${container}$" | grep -q .; then
        echo "999" # Not running
        return
    fi

    # Measure time to stop. If it takes > 4s, it likely hit the timeout.
    # We use python time.time() for millisecond precision
    local duration=$(python3 -c "
import subprocess
import time
start = time.time()
try:
    # Use 6s timeout for the command itself, pass --time=5 to docker
    subprocess.run(['docker', 'stop', '--time=5', '$container'], timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
except subprocess.TimeoutExpired:
    pass
end = time.time()
print(f'{end - start:.2f}')
")
    echo "$duration"
}

# ── Check Fixed Containers ───────────────────────────────────────────────────
# 1. acme-webserver-fixed
WEBSERVER_RUNNING=$(docker ps -q --filter "name=^acme-webserver-fixed$" | grep -c .)
WEBSERVER_STOP_TIME="999"
WEBSERVER_CMD_FORM=""
if [ "$WEBSERVER_RUNNING" -eq 1 ]; then
    WEBSERVER_STOP_TIME=$(measure_stop_time "acme-webserver-fixed")
    # Restart for inspection
    docker start acme-webserver-fixed >/dev/null 2>&1
    # Check if CMD is exec form (JSON array) or shell form (string)
    # This heuristic checks if the raw config CMD looks like ["..."]
    WEBSERVER_CMD_FORM=$(docker inspect acme-webserver-fixed --format '{{json .Config.Cmd}}')
fi

# 2. acme-scheduler-fixed
SCHEDULER_RUNNING=$(docker ps -q --filter "name=^acme-scheduler-fixed$" | grep -c .)
SCHEDULER_STOP_TIME="999"
if [ "$SCHEDULER_RUNNING" -eq 1 ]; then
    SCHEDULER_STOP_TIME=$(measure_stop_time "acme-scheduler-fixed")
    docker start acme-scheduler-fixed >/dev/null 2>&1
fi

# 3. acme-processor-fixed
PROCESSOR_RUNNING=$(docker ps -q --filter "name=^acme-processor-fixed$" | grep -c .)
PROCESSOR_STOP_TIME="999"
PROCESSOR_HAS_INIT="false"
if [ "$PROCESSOR_RUNNING" -eq 1 ]; then
    PROCESSOR_STOP_TIME=$(measure_stop_time "acme-processor-fixed")
    docker start acme-processor-fixed >/dev/null 2>&1
    
    # Check for init system
    INIT_CFG=$(docker inspect acme-processor-fixed --format '{{.HostConfig.Init}}')
    ENTRYPOINT=$(docker inspect acme-processor-fixed --format '{{json .Config.Entrypoint}}')
    
    if [ "$INIT_CFG" == "true" ]; then
        PROCESSOR_HAS_INIT="true"
    elif [[ "$ENTRYPOINT" == *"tini"* ]]; then
        PROCESSOR_HAS_INIT="true"
    fi
fi

# ── Check Originals Stopped ──────────────────────────────────────────────────
ORIGINALS_STOPPED=0
if [ -z "$(docker ps -q --filter "name=^acme-webserver$")" ] && \
   [ -z "$(docker ps -q --filter "name=^acme-scheduler$")" ] && \
   [ -z "$(docker ps -q --filter "name=^acme-processor$")" ]; then
    ORIGINALS_STOPPED=1
fi

# ── Check Report ─────────────────────────────────────────────────────────────
REPORT_PATH="/home/ga/Desktop/signal_handling_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # Capture first 1000 chars
fi

# ── Export JSON ──────────────────────────────────────────────────────────────
cat > /tmp/signal_result.json <<EOF
{
    "task_start": $TASK_START,
    "webserver_running": $WEBSERVER_RUNNING,
    "webserver_stop_time": $WEBSERVER_STOP_TIME,
    "webserver_cmd_form": $(echo "$WEBSERVER_CMD_FORM" | grep -q "^\\[" && echo "true" || echo "false"),
    "scheduler_running": $SCHEDULER_RUNNING,
    "scheduler_stop_time": $SCHEDULER_STOP_TIME,
    "processor_running": $PROCESSOR_RUNNING,
    "processor_stop_time": $PROCESSOR_STOP_TIME,
    "processor_has_init": $PROCESSOR_HAS_INIT,
    "originals_stopped": $ORIGINALS_STOPPED,
    "report_exists": $REPORT_EXISTS,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R -s '.')
}
EOF

# Clean up fixed containers (optional, but good hygiene)
docker rm -f acme-webserver-fixed acme-scheduler-fixed acme-processor-fixed 2>/dev/null || true

echo "Result saved to /tmp/signal_result.json"
cat /tmp/signal_result.json