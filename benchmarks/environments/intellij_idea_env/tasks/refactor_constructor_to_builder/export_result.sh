#!/bin/bash
set -e
echo "=== Exporting refactor_constructor_to_builder result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/iot-device-manager"
RESULT_JSON="/tmp/task_result.json"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Capture file contents for verification
MODEL_FILE="$PROJECT_DIR/src/main/java/com/iot/manager/model/SmartHomeDevice.java"
SERVICE_FILE="$PROJECT_DIR/src/main/java/com/iot/manager/service/DeviceService.java"
TEST_FILE="$PROJECT_DIR/src/test/java/com/iot/manager/service/DeviceServiceTest.java"

MODEL_CONTENT=""
SERVICE_CONTENT=""
TEST_CONTENT=""
[ -f "$MODEL_FILE" ] && MODEL_CONTENT=$(cat "$MODEL_FILE")
[ -f "$SERVICE_FILE" ] && SERVICE_CONTENT=$(cat "$SERVICE_FILE")
[ -f "$TEST_FILE" ] && TEST_CONTENT=$(cat "$TEST_FILE")

# 3. Run Maven Build and Tests
echo "Running maven tests..."
cd "$PROJECT_DIR"

# Clean first to ensure we aren't seeing old builds
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean > /dev/null 2>&1 || true

# Run compile first
COMPILE_SUCCESS=false
if JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -DskipTests > /tmp/mvn_compile.log 2>&1; then
    COMPILE_SUCCESS=true
fi

# Run tests
TESTS_PASSED=false
TEST_EXIT_CODE=1
if [ "$COMPILE_SUCCESS" = "true" ]; then
    if JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test > /tmp/mvn_test.log 2>&1; then
        TESTS_PASSED=true
        TEST_EXIT_CODE=0
    fi
fi

# 4. Check timestamps (Anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED=false
if [ -f "$MODEL_FILE" ]; then
    MOD_TIME=$(stat -c %Y "$MODEL_FILE")
    if [ "$MOD_TIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED=true
    fi
fi

# 5. Construct JSON result
# Use python to safely escape strings
cat <<EOF > /tmp/json_gen.py
import json

model_content = """$MODEL_CONTENT"""
service_content = """$SERVICE_CONTENT"""
test_content = """$TEST_CONTENT"""

result = {
    "compile_success": $COMPILE_SUCCESS,
    "tests_passed": $TESTS_PASSED,
    "model_content": model_content,
    "service_content": service_content,
    "test_content": test_content,
    "file_modified": $FILE_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}

print(json.dumps(result))
EOF

python3 /tmp/json_gen.py > "$RESULT_JSON"

# Fix permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="