#!/bin/bash
# Export script for Publish Test Results task

echo "=== Exporting Publish Test Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

JOB_NAME="QA-Test-Suite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Initialize result variables
JOB_EXISTS="false"
JOB_CLASS=""
BUILD_EXISTS="false"
BUILD_NUMBER=0
BUILD_RESULT="null"
BUILD_TIMESTAMP=0
HAS_TEST_REPORT="false"
TOTAL_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
PASS_COUNT=0

# Check if job exists
echo "Checking for job '$JOB_NAME'..."
JOB_INFO=$(jenkins_api "job/${JOB_NAME}/api/json" 2>/dev/null)

if [ -n "$JOB_INFO" ] && echo "$JOB_INFO" | grep -q "_class"; then
    JOB_EXISTS="true"
    JOB_CLASS=$(echo "$JOB_INFO" | jq -r '._class' 2>/dev/null)
    echo "Job found! Class: $JOB_CLASS"

    # Check for last build
    LAST_BUILD_INFO=$(jenkins_api "job/${JOB_NAME}/lastBuild/api/json" 2>/dev/null)
    
    if [ -n "$LAST_BUILD_INFO" ] && echo "$LAST_BUILD_INFO" | grep -q "number"; then
        BUILD_EXISTS="true"
        BUILD_NUMBER=$(echo "$LAST_BUILD_INFO" | jq -r '.number' 2>/dev/null)
        BUILD_RESULT=$(echo "$LAST_BUILD_INFO" | jq -r '.result' 2>/dev/null)
        BUILD_TIMESTAMP=$(echo "$LAST_BUILD_INFO" | jq -r '.timestamp' 2>/dev/null)
        
        echo "Build #$BUILD_NUMBER found. Result: $BUILD_RESULT"

        # Check for test results
        TEST_REPORT=$(jenkins_api "job/${JOB_NAME}/${BUILD_NUMBER}/testReport/api/json" 2>/dev/null)
        
        if [ -n "$TEST_REPORT" ] && echo "$TEST_REPORT" | grep -q "totalCount"; then
            HAS_TEST_REPORT="true"
            TOTAL_COUNT=$(echo "$TEST_REPORT" | jq -r '.totalCount' 2>/dev/null)
            FAIL_COUNT=$(echo "$TEST_REPORT" | jq -r '.failCount' 2>/dev/null)
            SKIP_COUNT=$(echo "$TEST_REPORT" | jq -r '.skipCount' 2>/dev/null)
            PASS_COUNT=$(echo "$TEST_REPORT" | jq -r '.passCount' 2>/dev/null)
            
            echo "Test Report: Total=$TOTAL_COUNT, Fail=$FAIL_COUNT, Skip=$SKIP_COUNT, Pass=$PASS_COUNT"
        else
            echo "No test report found for build #$BUILD_NUMBER"
        fi
    else
        echo "No builds found for job"
    fi
else
    echo "Job '$JOB_NAME' not found"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/publish_results.XXXXXX.json)
jq -n \
    --argjson job_exists "$JOB_EXISTS" \
    --arg job_class "$JOB_CLASS" \
    --argjson build_exists "$BUILD_EXISTS" \
    --argjson build_number "$BUILD_NUMBER" \
    --arg build_result "$BUILD_RESULT" \
    --argjson build_timestamp "$BUILD_TIMESTAMP" \
    --argjson task_start "$TASK_START" \
    --argjson has_test_report "$HAS_TEST_REPORT" \
    --argjson total_count "$TOTAL_COUNT" \
    --argjson fail_count "$FAIL_COUNT" \
    --argjson skip_count "$SKIP_COUNT" \
    --argjson pass_count "$PASS_COUNT" \
    '{
        job_exists: $job_exists,
        job_class: $job_class,
        build_exists: $build_exists,
        build_number: $build_number,
        build_result: $build_result,
        build_timestamp: $build_timestamp,
        task_start_time_ms: ($task_start * 1000),
        has_test_report: $has_test_report,
        test_counts: {
            total: $total_count,
            fail: $fail_count,
            skip: $skip_count,
            pass: $pass_count
        }
    }' > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="