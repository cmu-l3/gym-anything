#!/bin/bash
# Export script for Install & Configure Plugin task
set -e

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Jenkins might be restarting or down, try to wait for it
echo "Waiting for Jenkins to be responsive (in case of restart)..."
wait_for_jenkins_api 60 || echo "WARNING: Jenkins API did not respond in time"

# 1. Check if Plugin is Installed
echo "Checking plugin status..."
PLUGIN_INSTALLED="false"
PLUGIN_ACTIVE="false"
PLUGIN_INFO=$(jenkins_api "pluginManager/api/json?depth=1" 2>/dev/null)

if [ -n "$PLUGIN_INFO" ]; then
    # Check for timestamper
    TIMESTAMPER_DATA=$(echo "$PLUGIN_INFO" | jq '.plugins[] | select(.shortName == "timestamper")' 2>/dev/null)
    if [ -n "$TIMESTAMPER_DATA" ]; then
        PLUGIN_INSTALLED="true"
        PLUGIN_ACTIVE=$(echo "$TIMESTAMPER_DATA" | jq -r '.active' 2>/dev/null)
        echo "Timestamper plugin found (Active: $PLUGIN_ACTIVE)"
    else
        echo "Timestamper plugin NOT found"
    fi
else
    echo "Could not fetch plugin list"
fi

# 2. Check Job Configuration
JOB_NAME="QA-Test-Runner"
CONFIG_HAS_TIMESTAMP="false"
CONFIG_CHANGED="false"

if job_exists "$JOB_NAME"; then
    CURRENT_CONFIG=$(get_job_config "$JOB_NAME")
    
    # Check for wrapper class in config
    if echo "$CURRENT_CONFIG" | grep -q "hudson.plugins.timestamper.TimestamperBuildWrapper"; then
        CONFIG_HAS_TIMESTAMP="true"
        echo "Job config contains Timestamper wrapper"
    else
        echo "Job config does NOT contain Timestamper wrapper"
    fi
    
    # Check if config changed from initial
    CURRENT_HASH=$(echo "$CURRENT_CONFIG" | md5sum)
    INITIAL_HASH=$(cat /tmp/initial_config_hash.txt 2>/dev/null || echo "")
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        CONFIG_CHANGED="true"
    fi
else
    echo "Job $JOB_NAME not found"
fi

# 3. Check Build Execution
BUILD_COMPLETED="false"
BUILD_TIMESTAMP_OK="false"
CONSOLE_HAS_TIMESTAMPS="false"
BUILD_ID="0"

LAST_BUILD=$(jenkins_api "job/$JOB_NAME/lastBuild/api/json" 2>/dev/null)
if [ -n "$LAST_BUILD" ] && [ "$LAST_BUILD" != "null" ]; then
    BUILD_ID=$(echo "$LAST_BUILD" | jq -r '.number')
    RESULT=$(echo "$LAST_BUILD" | jq -r '.result')
    BUILD_TIME_MS=$(echo "$LAST_BUILD" | jq -r '.timestamp')
    
    # Convert task start to ms
    TASK_START_MS=$((TASK_START * 1000))
    
    if [ "$BUILD_TIME_MS" -gt "$TASK_START_MS" ]; then
        BUILD_TIMESTAMP_OK="true"
    fi
    
    if [ "$RESULT" != "null" ] && [ "$RESULT" != "BUILDING" ]; then
        BUILD_COMPLETED="true"
    fi
    
    # 4. Check Console Output for Timestamps
    # Timestamps look like "09:12:34  Phase 1..." or similar depending on config
    # We fetch console text and look for time patterns at start of lines
    CONSOLE_TEXT=$(jenkins_api "job/$JOB_NAME/$BUILD_ID/consoleText" 2>/dev/null)
    
    # Check for typical timestamp patterns: HH:MM:SS or YYYY-MM-DD
    if echo "$CONSOLE_TEXT" | grep -E "^[0-9]{2}:[0-9]{2}:[0-9]{2}" > /dev/null; then
        CONSOLE_HAS_TIMESTAMPS="true"
        echo "Timestamps detected in console output"
    elif echo "$CONSOLE_TEXT" | grep -E "^[0-9]{4}-[0-9]{2}-[0-9]{2}" > /dev/null; then
        CONSOLE_HAS_TIMESTAMPS="true"
        echo "Date/Timestamps detected in console output"
    else
        echo "No timestamps detected in console output"
    fi
fi

# 5. Check if plugin was pre-installed (Anti-gaming)
PLUGIN_PRE_INSTALLED="false"
if grep -q "timestamper" /tmp/initial_plugins.txt 2>/dev/null; then
    PLUGIN_PRE_INSTALLED="true"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "plugin_installed": $PLUGIN_INSTALLED,
    "plugin_active": $PLUGIN_ACTIVE,
    "plugin_pre_installed": $PLUGIN_PRE_INSTALLED,
    "config_has_timestamp": $CONFIG_HAS_TIMESTAMP,
    "config_changed": $CONFIG_CHANGED,
    "build_completed": $BUILD_COMPLETED,
    "build_timestamp_valid": $BUILD_TIMESTAMP_OK,
    "console_has_timestamps": $CONSOLE_HAS_TIMESTAMPS,
    "last_build_id": $BUILD_ID,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to safe location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="