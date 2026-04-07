#!/bin/bash
echo "=== Exporting Channel Watchdog Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. IDENTIFY CHANNELS
echo "Identifying channels..."
TARGET_ID=$(get_channel_id "Unstable_Service")
WATCHDOG_ID=$(get_channel_id "System_Watchdog")

TARGET_EXISTS="false"
WATCHDOG_EXISTS="false"
[ -n "$TARGET_ID" ] && TARGET_EXISTS="true"
[ -n "$WATCHDOG_ID" ] && WATCHDOG_EXISTS="true"

echo "Target ID: $TARGET_ID (Exists: $TARGET_EXISTS)"
echo "Watchdog ID: $WATCHDOG_ID (Exists: $WATCHDOG_EXISTS)"

# 2. CHECK CONFIGURATION (Polling)
POLLING_INTERVAL=0
if [ "$WATCHDOG_EXISTS" = "true" ]; then
    # Get channel XML
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$WATCHDOG_ID';" 2>/dev/null || true)
    
    # Extract polling frequency (JavaScript Reader)
    # Looking for <pollingFrequency>10000</pollingFrequency>
    POLLING_INTERVAL=$(echo "$CHANNEL_XML" | grep -oP '(?<=<pollingFrequency>)\d+(?=</pollingFrequency>)' | head -1 || echo "0")
fi
echo "Watchdog polling interval: $POLLING_INTERVAL"

# 3. DYNAMIC VERIFICATION (The "Chaos Monkey" Test)
AUTO_RESTART_SUCCESS="false"
TEST_ATTEMPTED="false"

if [ "$TARGET_EXISTS" = "true" ] && [ "$WATCHDOG_EXISTS" = "true" ]; then
    echo "Starting dynamic verification..."
    TEST_ATTEMPTED="true"

    # Ensure Watchdog is STARTED
    echo "Ensuring Watchdog is started..."
    api_call_json POST "/channels/$WATCHDOG_ID/start"
    
    # Ensure Target is STARTED initially
    echo "Ensuring Target is started..."
    api_call_json POST "/channels/$TARGET_ID/start"
    sleep 5
    
    INITIAL_STATUS=$(get_channel_status_api "$TARGET_ID")
    echo "Initial Target Status: $INITIAL_STATUS"
    
    if [ "$INITIAL_STATUS" = "STARTED" ]; then
        # STOP the target channel
        echo "Stopping Target Channel..."
        api_call_json POST "/channels/$TARGET_ID/stop"
        sleep 2
        
        STOPPED_STATUS=$(get_channel_status_api "$TARGET_ID")
        echo "Status after stop: $STOPPED_STATUS"
        
        if [ "$STOPPED_STATUS" != "STARTED" ]; then
            echo "Target successfully stopped. Waiting 25 seconds for watchdog (poll interval is usually 10s)..."
            sleep 25
            
            # Check if it came back up
            FINAL_STATUS=$(get_channel_status_api "$TARGET_ID")
            echo "Final Target Status: $FINAL_STATUS"
            
            if [ "$FINAL_STATUS" = "STARTED" ] || [ "$FINAL_STATUS" = "STARTING" ]; then
                AUTO_RESTART_SUCCESS="true"
                echo "SUCCESS: Channel automatically restarted!"
            else
                echo "FAILURE: Channel did not restart."
            fi
        else
            echo "Could not stop channel (status remained STARTED). Test inconclusive."
        fi
    else
        echo "Could not start target channel initially. Skipping test."
    fi
else
    echo "Channels missing, skipping dynamic test."
fi

# 4. LOG FILE VERIFICATION
LOG_FILE="/home/ga/watchdog.log"
LOG_EXISTS="false"
LOG_HAS_CONTENT="false"
LOG_CONTENT_PREVIEW=""

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    # Check if file has content
    if [ -s "$LOG_FILE" ]; then
        LOG_HAS_CONTENT="true"
        # Read last 3 lines
        LOG_CONTENT_PREVIEW=$(tail -n 3 "$LOG_FILE" | base64 -w 0)
    fi
fi

# 5. EXPORT JSON
JSON_CONTENT=$(cat <<EOF
{
    "target_exists": $TARGET_EXISTS,
    "watchdog_exists": $WATCHDOG_EXISTS,
    "target_id": "$TARGET_ID",
    "watchdog_id": "$WATCHDOG_ID",
    "polling_interval": $POLLING_INTERVAL,
    "test_attempted": $TEST_ATTEMPTED,
    "auto_restart_success": $AUTO_RESTART_SUCCESS,
    "log_exists": $LOG_EXISTS,
    "log_has_content": $LOG_HAS_CONTENT,
    "log_content_base64": "$LOG_CONTENT_PREVIEW",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="