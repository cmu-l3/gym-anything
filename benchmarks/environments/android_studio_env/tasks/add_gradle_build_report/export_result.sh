#!/bin/bash
set -e
echo "=== Exporting add_gradle_build_report results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/TodoApp"
REPORT_PATH="$PROJECT_DIR/app/build/reports/build-report.json"
BUILD_FILE="$PROJECT_DIR/app/build.gradle.kts"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Attempt to run the task to verify it works
echo "Verifying task execution..."
TASK_EXIT_CODE=1
cd "$PROJECT_DIR"

# Ensure gradlew is executable
chmod +x gradlew

# Run the task (with timeout to prevent hanging)
timeout 120s su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && ./gradlew :app:generateBuildReport --no-daemon" > /tmp/gradle_execution.log 2>&1
TASK_EXIT_CODE=$?

# 3. Check output file
OUTPUT_EXISTS="false"
OUTPUT_CONTENT="{}"
FILE_MTIME=0

if [ -f "$REPORT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$REPORT_PATH")
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH")
fi

# 4. Read build.gradle.kts content (to check for hardcoding)
BUILD_FILE_CONTENT=""
if [ -f "$BUILD_FILE" ]; then
    BUILD_FILE_CONTENT=$(cat "$BUILD_FILE")
fi

# 5. Check if file was created/modified during task
FILE_CREATED_DURING_TASK="false"
if [ "$OUTPUT_EXISTS" = "true" ] && [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# 6. Escape content for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$1"
}

OUTPUT_CONTENT_ESCAPED=$(escape_json "$OUTPUT_CONTENT")
BUILD_FILE_ESCAPED=$(escape_json "$BUILD_FILE_CONTENT")
GRADLE_LOG_ESCAPED=$(escape_json "$(cat /tmp/gradle_execution.log 2>/dev/null | tail -n 50)")

# 7. Create result JSON
cat > /tmp/task_result.json <<EOF
{
    "task_exit_code": $TASK_EXIT_CODE,
    "output_exists": $OUTPUT_EXISTS,
    "output_content": $OUTPUT_CONTENT_ESCAPED,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "build_file_content": $BUILD_FILE_ESCAPED,
    "gradle_log": $GRADLE_LOG_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"