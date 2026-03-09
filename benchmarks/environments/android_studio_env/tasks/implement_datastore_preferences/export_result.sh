#!/bin/bash
echo "=== Exporting implement_datastore_preferences result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/PodcastPlayer"
BUILD_FILE="$PROJECT_DIR/app/build.gradle.kts"
REPO_FILE="$PROJECT_DIR/app/src/main/java/com/example/podcastplayer/data/SettingsRepository.kt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Capture File Contents
BUILD_CONTENT=""
if [ -f "$BUILD_FILE" ]; then
    BUILD_CONTENT=$(cat "$BUILD_FILE")
fi

REPO_CONTENT=""
if [ -f "$REPO_FILE" ]; then
    REPO_CONTENT=$(cat "$REPO_FILE")
fi

# 2. Run Tests explicitly to get a fresh report
echo "Running tests..."
cd "$PROJECT_DIR"
# Use system gradle if wrapper is our dummy one, or real wrapper
chmod +x gradlew
./gradlew testDebugUnitTest --no-daemon > /tmp/gradle_test_output.log 2>&1
GRADLE_EXIT_CODE=$?

# 3. Parse Test Results
TEST_RESULTS_DIR="$PROJECT_DIR/app/build/test-results/testDebugUnitTest"
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

if [ -d "$TEST_RESULTS_DIR" ]; then
    for xml in "$TEST_RESULTS_DIR"/*.xml; do
        if [ -f "$xml" ]; then
             # Simple regex parsing for xml attributes
             T=$(grep -oP 'tests="\K[0-9]+' "$xml" | head -1 || echo 0)
             F=$(grep -oP 'failures="\K[0-9]+' "$xml" | head -1 || echo 0)
             E=$(grep -oP 'errors="\K[0-9]+' "$xml" | head -1 || echo 0)
             S=$(grep -oP 'skipped="\K[0-9]+' "$xml" | head -1 || echo 0)
             
             TOTAL_TESTS=$((TOTAL_TESTS + T))
             FAILED_TESTS=$((FAILED_TESTS + F + E))
             # Passed is total - (failures + errors + skipped)
             PASSED_TESTS=$((PASSED_TESTS + T - F - E - S))
        fi
    done
fi

# 4. Create JSON Result
# Escape for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'
}

BUILD_ESCAPED=$(escape_json "$BUILD_CONTENT")
REPO_ESCAPED=$(escape_json "$REPO_CONTENT")

cat > /tmp/task_result.json << EOF
{
    "build_file_exists": $([ -f "$BUILD_FILE" ] && echo "true" || echo "false"),
    "repo_file_exists": $([ -f "$REPO_FILE" ] && echo "true" || echo "false"),
    "build_content": $BUILD_ESCAPED,
    "repo_content": $REPO_ESCAPED,
    "gradle_exit_code": $GRADLE_EXIT_CODE,
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "timestamp": $(date +%s)
}
EOF

# Safe copy to /tmp/task_result.json is already done by cat
# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json