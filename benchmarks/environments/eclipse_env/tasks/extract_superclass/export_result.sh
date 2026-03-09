#!/bin/bash
echo "=== Exporting Extract Superclass result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/notification-system"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if the AbstractNotificationService.java file exists
SUPERCLASS_EXISTS="false"
if [ -f "$PROJECT_DIR/src/main/java/com/acme/notify/AbstractNotificationService.java" ]; then
    SUPERCLASS_EXISTS="true"
fi

# Run compilation via Maven
echo "Running Maven Compile..."
COMPILE_EXIT_CODE=0
su - ga -c "cd $PROJECT_DIR && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q" > /tmp/maven_compile.log 2>&1 || COMPILE_EXIT_CODE=$?

# Run tests via Maven
echo "Running Maven Test..."
TEST_EXIT_CODE=0
TEST_OUTPUT=""
su - ga -c "cd $PROJECT_DIR && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -q" > /tmp/maven_test.log 2>&1 || TEST_EXIT_CODE=$?

# Parse test results
TESTS_RUN=0
TESTS_FAILED=0
TESTS_ERRORS=0

if [ -f "$PROJECT_DIR/target/surefire-reports/TEST-com.acme.notify.NotificationServiceTest.xml" ]; then
    REPORT_FILE="$PROJECT_DIR/target/surefire-reports/TEST-com.acme.notify.NotificationServiceTest.xml"
    TESTS_RUN=$(grep -oP 'tests="\K[0-9]+' "$REPORT_FILE" 2>/dev/null | head -1 || echo "0")
    TESTS_FAILED=$(grep -oP 'failures="\K[0-9]+' "$REPORT_FILE" 2>/dev/null | head -1 || echo "0")
    TESTS_ERRORS=$(grep -oP 'errors="\K[0-9]+' "$REPORT_FILE" 2>/dev/null | head -1 || echo "0")
fi

# Capture anti-gaming timestamp
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)

# Create JSON result using python to handle quoting safely
python3 << EOF
import json
import os

result = {
    "superclass_exists": $SUPERCLASS_EXISTS,
    "compile_exit_code": $COMPILE_EXIT_CODE,
    "test_exit_code": $TEST_EXIT_CODE,
    "tests_run": int("$TESTS_RUN"),
    "tests_failed": int("$TESTS_FAILED"),
    "tests_errors": int("$TESTS_ERRORS"),
    "task_start_time": $TASK_START_TIME,
    "task_end_time": $TASK_END_TIME,
    "screenshot_path": "/tmp/task_final.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

# Ensure result file permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="