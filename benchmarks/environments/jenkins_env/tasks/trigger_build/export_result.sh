#!/bin/bash
# Export script for Trigger Build task
# Checks if a build was triggered and completed successfully

echo "=== Exporting Trigger Build Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get test job name
TEST_JOB_NAME="Test-Build-Job"

# Check if test job exists
if ! job_exists "$TEST_JOB_NAME"; then
    echo "ERROR: Test job '$TEST_JOB_NAME' not found!"

    # Create error result
    TEMP_JSON=$(mktemp /tmp/trigger_build_result.XXXXXX.json)
    cat > "$TEMP_JSON" << 'EOF'
{
    "job_exists": false,
    "build_triggered": false,
    "build_count": 0,
    "last_build": null,
    "export_timestamp": "ERROR: Test job not found"
}
EOF
    rm -f /tmp/trigger_build_result.json 2>/dev/null || sudo rm -f /tmp/trigger_build_result.json 2>/dev/null || true
    cp "$TEMP_JSON" /tmp/trigger_build_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/trigger_build_result.json
    chmod 666 /tmp/trigger_build_result.json 2>/dev/null || sudo chmod 666 /tmp/trigger_build_result.json 2>/dev/null || true
    rm -f "$TEMP_JSON"
    echo "=== Export Complete (ERROR) ==="
    exit 0
fi

echo "Test job '$TEST_JOB_NAME' found"

# Get job status
JOB_STATUS=$(get_job_status "$TEST_JOB_NAME" 2>/dev/null)

# Extract build count and last build number from job-level API
BUILD_COUNT=$(echo "$JOB_STATUS" | jq -r '.builds | length' 2>/dev/null || echo "0")
LAST_BUILD_NUMBER=$(echo "$JOB_STATUS" | jq -r '.lastBuild.number // "null"' 2>/dev/null || echo "null")

# Determine if build was triggered
INITIAL_BUILD_COUNT=$(cat /tmp/initial_build_count 2>/dev/null || echo "0")
BUILD_TRIGGERED="false"

if [ "$BUILD_COUNT" -gt "$INITIAL_BUILD_COUNT" ] 2>/dev/null; then
    BUILD_TRIGGERED="true"
    echo "Build was triggered! (count: $INITIAL_BUILD_COUNT -> $BUILD_COUNT)"
else
    echo "No new builds detected (count: $BUILD_COUNT)"
fi

# Get detailed last build info from the BUILD-level API endpoint
LAST_BUILD_INFO="null"
LAST_BUILD_RESULT="null"
LAST_BUILD_BUILDING="false"
LAST_BUILD_URL=""
LAST_BUILD_DURATION=0
LAST_BUILD_TIMESTAMP=0

if [ "$LAST_BUILD_NUMBER" != "null" ] && [ "$LAST_BUILD_NUMBER" != "0" ]; then
    echo "Fetching detailed last build info from build API..."

    # Wait briefly for build to finish if still running
    for wait_i in $(seq 1 12); do
        LAST_BUILD_DATA=$(jenkins_api "job/${TEST_JOB_NAME}/lastBuild/api/json" 2>/dev/null)
        LAST_BUILD_BUILDING=$(echo "$LAST_BUILD_DATA" | jq -r '.building // false' 2>/dev/null || echo "false")
        if [ "$LAST_BUILD_BUILDING" = "false" ]; then
            break
        fi
        echo "  Build still running, waiting... (${wait_i})"
        sleep 5
    done

    if [ -n "$LAST_BUILD_DATA" ]; then
        LAST_BUILD_RESULT=$(echo "$LAST_BUILD_DATA" | jq -r '.result // "null"' 2>/dev/null || echo "null")
        LAST_BUILD_URL=$(echo "$LAST_BUILD_DATA" | jq -r '.url // ""' 2>/dev/null || echo "")
        LAST_BUILD_DURATION=$(echo "$LAST_BUILD_DATA" | jq -r '.duration // 0' 2>/dev/null || echo "0")
        LAST_BUILD_TIMESTAMP=$(echo "$LAST_BUILD_DATA" | jq -r '.timestamp // 0' 2>/dev/null || echo "0")
    fi
fi

echo ""
echo "Build status:"
echo "  Build count: $BUILD_COUNT"
echo "  Last build number: $LAST_BUILD_NUMBER"
echo "  Last build result: $LAST_BUILD_RESULT"
echo "  Currently building: $LAST_BUILD_BUILDING"

# Create final result JSON using jq for safe escaping
TEMP_JSON=$(mktemp /tmp/trigger_build_result.XXXXXX.json)
if [ "$LAST_BUILD_NUMBER" != "null" ] && [ "$LAST_BUILD_NUMBER" != "0" ] && [ -n "$LAST_BUILD_DATA" ]; then
    jq -n \
        --argjson build_triggered "$BUILD_TRIGGERED" \
        --argjson build_count "${BUILD_COUNT:-0}" \
        --argjson initial_count "${INITIAL_BUILD_COUNT:-0}" \
        --argjson build_number "${LAST_BUILD_NUMBER:-0}" \
        --arg build_result "$LAST_BUILD_RESULT" \
        --argjson building "$LAST_BUILD_BUILDING" \
        --arg build_url "$LAST_BUILD_URL" \
        --argjson duration "${LAST_BUILD_DURATION:-0}" \
        --argjson build_timestamp "${LAST_BUILD_TIMESTAMP:-0}" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            job_exists: true,
            build_triggered: $build_triggered,
            build_count: $build_count,
            initial_build_count: $initial_count,
            last_build: {
                number: $build_number,
                result: $build_result,
                building: $building,
                url: $build_url,
                duration_ms: $duration,
                timestamp: $build_timestamp
            },
            export_timestamp: $timestamp
        }' > "$TEMP_JSON"
else
    jq -n \
        --argjson build_triggered "$BUILD_TRIGGERED" \
        --argjson build_count "${BUILD_COUNT:-0}" \
        --argjson initial_count "${INITIAL_BUILD_COUNT:-0}" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            job_exists: true,
            build_triggered: $build_triggered,
            build_count: $build_count,
            initial_build_count: $initial_count,
            last_build: null,
            export_timestamp: $timestamp
        }' > "$TEMP_JSON"
fi

# Move temp file to final location (handles permission issues)
rm -f /tmp/trigger_build_result.json 2>/dev/null || sudo rm -f /tmp/trigger_build_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/trigger_build_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/trigger_build_result.json
chmod 666 /tmp/trigger_build_result.json 2>/dev/null || sudo chmod 666 /tmp/trigger_build_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/trigger_build_result.json"
cat /tmp/trigger_build_result.json

echo ""
echo "=== Export Complete ==="
