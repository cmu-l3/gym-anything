#!/bin/bash
# Export script for Configure Custom Workspace task

echo "=== Exporting Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

JOB_NAME="legacy-system-build"
EXPECTED_WS="/tmp/legacy_ws"

# 1. Get Job Configuration
echo "Fetching job config..."
JOB_CONFIG=$(get_job_config "$JOB_NAME" 2>/dev/null)
CUSTOM_WORKSPACE_XML=$(echo "$JOB_CONFIG" | grep -oP '<customWorkspace>\K[^<]+' || echo "")

# 2. Check Build Status
echo "Checking build status..."
LAST_BUILD_INFO=$(get_last_build "$JOB_NAME")
BUILD_NUMBER=$(echo "$LAST_BUILD_INFO" | jq -r '.number // 0')
BUILD_RESULT=$(echo "$LAST_BUILD_INFO" | jq -r '.result // "null"')
INITIAL_BUILD_COUNT=$(cat /tmp/initial_build_count 2>/dev/null || echo "0")

BUILD_TRIGGERED="false"
if [ "$BUILD_NUMBER" -gt "$INITIAL_BUILD_COUNT" ]; then
    BUILD_TRIGGERED="true"
fi

# 3. Analyze Console Log
echo "Analyzing console log..."
CONSOLE_LOG=$(get_build_console "$JOB_NAME" "$BUILD_NUMBER")
LOG_MATCH="false"
if echo "$CONSOLE_LOG" | grep -Fq "Building in workspace $EXPECTED_WS"; then
    LOG_MATCH="true"
fi

# 4. Check Filesystem (Anti-gaming)
echo "Checking filesystem..."
WS_EXISTS="false"
WS_HAS_FILES="false"

if [ -d "$EXPECTED_WS" ]; then
    WS_EXISTS="true"
    # Check if directory is not empty (should contain cloned repo)
    if [ "$(ls -A $EXPECTED_WS 2>/dev/null)" ]; then
        WS_HAS_FILES="true"
    fi
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/custom_workspace_result.XXXXXX.json)
jq -n \
    --arg job_name "$JOB_NAME" \
    --arg custom_workspace "$CUSTOM_WORKSPACE_XML" \
    --arg expected_workspace "$EXPECTED_WS" \
    --argjson build_triggered "$BUILD_TRIGGERED" \
    --arg build_result "$BUILD_RESULT" \
    --argjson log_match "$LOG_MATCH" \
    --argjson ws_exists "$WS_EXISTS" \
    --argjson ws_has_files "$WS_HAS_FILES" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        job_name: $job_name,
        config: {
            custom_workspace: $custom_workspace
        },
        build: {
            triggered: $build_triggered,
            result: $build_result,
            log_match: $log_match
        },
        filesystem: {
            exists: $ws_exists,
            has_files: $ws_has_files
        },
        export_timestamp: $timestamp
    }' > "$TEMP_JSON"

# Move to final location
rm -f /tmp/custom_workspace_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/custom_workspace_result.json
chmod 666 /tmp/custom_workspace_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/custom_workspace_result.json