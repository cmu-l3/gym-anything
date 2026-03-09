#!/bin/bash
echo "=== Exporting refactor_introduce_parameter_object result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/legacy-payment-module"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Attempt to build and test the project
cd "$PROJECT_DIR"
BUILD_OUTPUT=$(mvn clean compile test 2>&1)
BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    BUILD_SUCCESS="true"
else
    BUILD_SUCCESS="false"
fi

# 2. Find the new class file (TransactionRequest.java)
# It might be in the same package or a subpackage depending on agent choice
NEW_CLASS_PATH=$(find "$PROJECT_DIR/src/main/java" -name "TransactionRequest.java" | head -1)

NEW_CLASS_EXISTS="false"
NEW_CLASS_CONTENT=""
if [ -n "$NEW_CLASS_PATH" ]; then
    NEW_CLASS_EXISTS="true"
    NEW_CLASS_CONTENT=$(cat "$NEW_CLASS_PATH")
fi

# 3. Read the modified PaymentProcessor.java
PROCESSOR_CONTENT=""
PROCESSOR_PATH="$PROJECT_DIR/src/main/java/com/example/payments/PaymentProcessor.java"
if [ -f "$PROCESSOR_PATH" ]; then
    PROCESSOR_CONTENT=$(cat "$PROCESSOR_PATH")
fi

# 4. Read the updated caller code (App.java)
APP_CONTENT=""
APP_PATH="$PROJECT_DIR/src/main/java/com/example/payments/App.java"
if [ -f "$APP_PATH" ]; then
    APP_CONTENT=$(cat "$APP_PATH")
fi

# 5. Read the updated test code
TEST_CONTENT=""
TEST_PATH="$PROJECT_DIR/src/test/java/com/example/payments/PaymentServiceTest.java"
if [ -f "$TEST_PATH" ]; then
    TEST_CONTENT=$(cat "$TEST_PATH")
fi

# 6. Check if files were actually modified
MODIFIED="false"
INITIAL_SUM=$(cat /tmp/initial_checksum.txt 2>/dev/null | awk '{print $1}')
CURRENT_SUM=$(md5sum "$PROCESSOR_PATH" 2>/dev/null | awk '{print $1}')
if [ "$INITIAL_SUM" != "$CURRENT_SUM" ]; then
    MODIFIED="true"
fi

# Prepare JSON
# Python used for safe JSON escaping
python3 << PYEOF
import json
import os
import sys

result = {
    "build_success": ${BUILD_SUCCESS},
    "new_class_exists": ${NEW_CLASS_EXISTS},
    "modified": ${MODIFIED},
    "timestamp": "$(date -Iseconds)"
}

# Read contents safely
result["new_class_content"] = """${NEW_CLASS_CONTENT}"""
result["processor_content"] = """${PROCESSOR_CONTENT}"""
result["app_content"] = """${APP_CONTENT}"""
result["test_content"] = """${TEST_CONTENT}"""
result["build_output"] = """$(echo "$BUILD_OUTPUT" | tail -n 20)"""

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="