#!/bin/bash
# export_result.sh - Verify and export results for Water Monitoring Task
# This script runs INSIDE the container to verify the physics logic.

source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
APIKEY=$(get_apikey_write)

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# 1. Check Feeds Existence & Configuration
# -----------------------------------------------------------------------
FEED_TOTAL_ID=$(db_query "SELECT id FROM feeds WHERE name='water_total_m3' AND userid=1" 2>/dev/null | head -1)
FEED_FLOW_ID=$(db_query "SELECT id FROM feeds WHERE name='water_flow_lpm' AND userid=1" 2>/dev/null | head -1)

# Check feed configuration (Engine=5 (PHPFina), Interval=10)
TOTAL_CONFIG_OK="false"
FLOW_CONFIG_OK="false"

if [ -n "$FEED_TOTAL_ID" ]; then
    ENGINE=$(db_query "SELECT engine FROM feeds WHERE id=$FEED_TOTAL_ID" 2>/dev/null)
    # Options is a JSON string {"interval":10}, simplest to grep
    INTERVAL_CHECK=$(db_query "SELECT options FROM feeds WHERE id=$FEED_TOTAL_ID" 2>/dev/null | grep -o "10" || echo "")
    if [ "$ENGINE" = "5" ] && [ -n "$INTERVAL_CHECK" ]; then
        TOTAL_CONFIG_OK="true"
    fi
fi

if [ -n "$FEED_FLOW_ID" ]; then
    ENGINE=$(db_query "SELECT engine FROM feeds WHERE id=$FEED_FLOW_ID" 2>/dev/null)
    INTERVAL_CHECK=$(db_query "SELECT options FROM feeds WHERE id=$FEED_FLOW_ID" 2>/dev/null | grep -o "10" || echo "")
    if [ "$ENGINE" = "5" ] && [ -n "$INTERVAL_CHECK" ]; then
        FLOW_CONFIG_OK="true"
    fi
fi

# -----------------------------------------------------------------------
# 2. Physics Simulation Test (The real verification)
# We inject controlled values to test the agent's processing chain logic.
# -----------------------------------------------------------------------
echo "Running Physics Simulation Test..."

# Baseline: 20000 pulses
# Target Delta: 10 pulses over 10 seconds
# 10 pulses = 100 Liters
# Flow = 100L / 10s = 10 L/s = 600 L/min
# Total Volume = 20010 * 10L = 200100L = 200.1 m3

BASE_PULSES=20000
FINAL_PULSES=20010
TEST_TIMESTAMP=$(date +%s)
# Align timestamp to 10s boundary to help PHPFina (optional but good practice)
TEST_TIMESTAMP=$(( (TEST_TIMESTAMP / 10) * 10 ))

# Inject Baseline (T=0)
curl -s "${EMONCMS_URL}/input/post?apikey=${APIKEY}&node=utility_room&json={main_water_pulses:${BASE_PULSES}}&time=${TEST_TIMESTAMP}" >/dev/null

# Sleep slightly more than 10s to ensure the engine registers the interval
# Emoncms 'rate' processor relies on time difference between posts
sleep 11

# Inject Final (T=10)
NEXT_TIMESTAMP=$((TEST_TIMESTAMP + 10))
curl -s "${EMONCMS_URL}/input/post?apikey=${APIKEY}&node=utility_room&json={main_water_pulses:${FINAL_PULSES}}&time=${NEXT_TIMESTAMP}" >/dev/null

# Allow background processing to write to feeds (PHP-Fina uses buffer)
sleep 2

# Read Feed Values
# Emoncms feed/value endpoint returns the current value
VAL_TOTAL=$(curl -s "${EMONCMS_URL}/feed/value.json?apikey=${APIKEY}&id=${FEED_TOTAL_ID}" | grep -oE "[0-9.-]+" || echo "0")
VAL_FLOW=$(curl -s "${EMONCMS_URL}/feed/value.json?apikey=${APIKEY}&id=${FEED_FLOW_ID}" | grep -oE "[0-9.-]+" || echo "0")

echo "Physics Test Results:"
echo "  Input Baseline: $BASE_PULSES"
echo "  Input Final:    $FINAL_PULSES (Delta: 10)"
echo "  Measured Total: $VAL_TOTAL (Expected: ~200.1)"
echo "  Measured Flow:  $VAL_FLOW (Expected: ~600.0)"

# -----------------------------------------------------------------------
# 3. Anti-Gaming Check (Timestamps)
# -----------------------------------------------------------------------
FEEDS_CREATED_DURING_TASK="false"
# Check creation time of feeds (roughly via file mtime in /var/opt/emoncms/phpfina)
# Docker path mapping: feed datadir is inside container
# We can check if feed IDs are higher than what likely existed, or just check file presence
# Since we deleted feeds in setup, existence implies creation during task.
if [ -n "$FEED_TOTAL_ID" ] && [ -n "$FEED_FLOW_ID" ]; then
    FEEDS_CREATED_DURING_TASK="true"
fi

# -----------------------------------------------------------------------
# 4. Export to JSON
# -----------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "feed_total_exists": $([ -n "$FEED_TOTAL_ID" ] && echo "true" || echo "false"),
    "feed_flow_exists": $([ -n "$FEED_FLOW_ID" ] && echo "true" || echo "false"),
    "total_config_ok": $TOTAL_CONFIG_OK,
    "flow_config_ok": $FLOW_CONFIG_OK,
    "measured_total_m3": ${VAL_TOTAL:-0},
    "measured_flow_lpm": ${VAL_FLOW:-0},
    "physics_test_run": true,
    "feeds_created_during_task": $FEEDS_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="