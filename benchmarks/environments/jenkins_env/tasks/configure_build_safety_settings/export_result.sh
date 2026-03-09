#!/bin/bash
# Export script for Configure Build Safety Settings
# Exports the configuration of Production-Deploy to JSON

echo "=== Exporting Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TARGET_JOB="Production-Deploy"
UPSTREAM_JOB="Backend-Build"

# Initialize variables
JOB_FOUND="false"
CONCURRENT_BUILD="unknown"
QUIET_PERIOD="null"
BLOCK_UPSTREAM="false"
BACKEND_CONFIG_HASH=""

# Check if job exists
if job_exists "$TARGET_JOB"; then
    JOB_FOUND="true"
    
    # Fetch config.xml
    CONFIG_XML=$(get_job_config "$TARGET_JOB")
    
    # 1. Check Concurrent Build status
    # In XML, <concurrentBuild>true</concurrentBuild> means enabled.
    CONCURRENT_BUILD=$(echo "$CONFIG_XML" | xmlstarlet sel -t -v "//concurrentBuild" 2>/dev/null)
    # Handle case where tag might be missing (defaults vary, but we set it explicitly in setup)
    if [ -z "$CONCURRENT_BUILD" ]; then CONCURRENT_BUILD="false"; fi
    
    # 2. Check Quiet Period
    # Look for <quietPeriod>120</quietPeriod>
    QUIET_PERIOD=$(echo "$CONFIG_XML" | xmlstarlet sel -t -v "//quietPeriod" 2>/dev/null)
    if [ -z "$QUIET_PERIOD" ]; then QUIET_PERIOD="0"; fi
    
    # 3. Check Block When Upstream Building
    # Look for <blockBuildWhenUpstreamBuilding>true</blockBuildWhenUpstreamBuilding>
    BLOCK_UPSTREAM=$(echo "$CONFIG_XML" | xmlstarlet sel -t -v "//blockBuildWhenUpstreamBuilding" 2>/dev/null)
    if [ -z "$BLOCK_UPSTREAM" ]; then BLOCK_UPSTREAM="false"; fi
    
    echo "Extracted Configuration:"
    echo "  Concurrent: $CONCURRENT_BUILD"
    echo "  Quiet Period: $QUIET_PERIOD"
    echo "  Block Upstream: $BLOCK_UPSTREAM"
else
    echo "ERROR: Job $TARGET_JOB not found!"
fi

# Anti-gaming: Get hash of upstream job config to ensure it wasn't tampered with
if job_exists "$UPSTREAM_JOB"; then
    BACKEND_CONFIG_HASH=$(get_job_config "$UPSTREAM_JOB" | md5sum | cut -d' ' -f1)
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/safety_result.XXXXXX.json)
jq -n \
    --arg job_found "$JOB_FOUND" \
    --arg concurrent_build "$CONCURRENT_BUILD" \
    --arg quiet_period "$QUIET_PERIOD" \
    --arg block_upstream "$BLOCK_UPSTREAM" \
    --arg backend_hash "$BACKEND_CONFIG_HASH" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        job_found: ($job_found == "true"),
        config: {
            concurrent_build: ($concurrent_build == "true"),
            quiet_period: ($quiet_period | tonumber),
            block_upstream: ($block_upstream == "true")
        },
        backend_hash: $backend_hash,
        export_timestamp: $timestamp
    }' > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="