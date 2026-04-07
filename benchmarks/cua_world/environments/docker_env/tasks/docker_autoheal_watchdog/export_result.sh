#!/bin/bash
echo "=== Exporting Docker Autoheal Watchdog Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/projects/payment-gateway"

# 1. Static Analysis: Check for Healthcheck configuration
echo "Checking configuration..."
HAS_HEALTHCHECK=0
GATEWAY_CONFIG=$(docker inspect gateway 2>/dev/null || echo "{}")
if echo "$GATEWAY_CONFIG" | grep -q '"Healthcheck":'; then
    HAS_HEALTHCHECK=1
fi

# 2. Static Analysis: Check for Watchdog existence and Socket mount
echo "Checking watchdog..."
WATCHDOG_EXISTS=0
WATCHDOG_HAS_SOCKET=0
if docker ps --format '{{.Names}}' | grep -q "watchdog"; then
    WATCHDOG_EXISTS=1
    WATCHDOG_MOUNTS=$(docker inspect watchdog --format '{{json .HostConfig.Binds}}' 2>/dev/null)
    if echo "$WATCHDOG_MOUNTS" | grep -q "/var/run/docker.sock"; then
        WATCHDOG_HAS_SOCKET=1
    fi
fi

# 3. Dynamic Test: Functional Recovery
# This is the critical part. We will sabotage the app and watch if it gets restarted.
echo "Starting functional recovery test..."

RECOVERY_SUCCESS=0
DETECTED_UNHEALTHY=0
ORIGINAL_START_TIME=""
NEW_START_TIME=""

# Ensure stack is up
cd "$PROJECT_DIR"
docker compose up -d 2>/dev/null || true

# Wait for initial healthy state (give agent's watchdog time to init)
echo "Waiting for stack stability..."
for i in {1..15}; do
    HEALTH=$(docker inspect --format '{{.State.Health.Status}}' gateway 2>/dev/null || echo "unknown")
    if [ "$HEALTH" = "healthy" ]; then
        echo "Gateway is healthy."
        break
    fi
    sleep 2
done

# Record start time before sabotage
ORIGINAL_START_TIME=$(docker inspect --format '{{.State.StartedAt}}' gateway 2>/dev/null)
echo "Original Start Time: $ORIGINAL_START_TIME"

# Trigger Sabotage
echo "Triggering Sabotage (simulating deadlock)..."
curl -X POST http://localhost:8000/sabotage > /dev/null 2>&1 || true

# Monitor for restart (60 seconds timeout)
echo "Monitoring for auto-restart..."
for i in {1..12}; do
    sleep 5
    
    # Check if health becomes unhealthy (verifying the healthcheck works)
    CURRENT_HEALTH=$(docker inspect --format '{{.State.Health.Status}}' gateway 2>/dev/null)
    if [ "$CURRENT_HEALTH" = "unhealthy" ]; then
        DETECTED_UNHEALTHY=1
        echo "  [t=${i}x5s] Detected unhealthy state."
    fi

    # Check if start time changed
    CURRENT_START_TIME=$(docker inspect --format '{{.State.StartedAt}}' gateway 2>/dev/null)
    
    if [ "$CURRENT_START_TIME" != "$ORIGINAL_START_TIME" ] && [ -n "$CURRENT_START_TIME" ]; then
        echo "  [t=${i}x5s] RESTART DETECTED!"
        echo "  New Start Time: $CURRENT_START_TIME"
        RECOVERY_SUCCESS=1
        NEW_START_TIME="$CURRENT_START_TIME"
        break
    fi
    echo "  [t=${i}x5s] Status: $CURRENT_HEALTH | Start: $CURRENT_START_TIME"
done

# Validate watchdog is actually running code (basic check if it exited)
WATCHDOG_STATUS=$(get_container_status watchdog)

cat > /tmp/autoheal_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "has_healthcheck": $HAS_HEALTHCHECK,
    "watchdog_exists": $WATCHDOG_EXISTS,
    "watchdog_has_socket": $WATCHDOG_HAS_SOCKET,
    "detected_unhealthy": $DETECTED_UNHEALTHY,
    "recovery_success": $RECOVERY_SUCCESS,
    "watchdog_status": "$WATCHDOG_STATUS",
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "Result JSON:"
cat /tmp/autoheal_result.json
echo "=== Export Complete ==="