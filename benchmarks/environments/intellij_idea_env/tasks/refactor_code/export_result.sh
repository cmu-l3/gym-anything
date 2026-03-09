#!/bin/bash
echo "=== Exporting refactor_code result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/refactor-demo"
TARGET_FILE="$PROJECT_DIR/src/main/java/org/lable/oss/helloworld/Calculator.java"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Read current file content
CALC_CONTENT=""
if [ -f "$TARGET_FILE" ]; then
    CALC_CONTENT=$(cat "$TARGET_FILE" 2>/dev/null)
fi

# Try building the project
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q 2>/dev/null
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
fi

# Check class file
CLASS_EXISTS="false"
if [ -f "$PROJECT_DIR/target/classes/org/lable/oss/helloworld/Calculator.class" ]; then
    CLASS_EXISTS="true"
fi

# Escape content for JSON
CALC_ESCAPED=$(echo "$CALC_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "calculator_content": $CALC_ESCAPED,
    "build_success": $BUILD_SUCCESS,
    "class_exists": $CLASS_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
