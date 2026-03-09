#!/bin/bash
echo "=== Exporting fix_build_errors result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/gs-maven-broken"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Read current file contents
POM_CONTENT=""
HW_CONTENT=""
GR_CONTENT=""

if [ -f "$PROJECT_DIR/pom.xml" ]; then
    POM_CONTENT=$(cat "$PROJECT_DIR/pom.xml" 2>/dev/null)
fi
if [ -f "$PROJECT_DIR/src/main/java/hello/HelloWorld.java" ]; then
    HW_CONTENT=$(cat "$PROJECT_DIR/src/main/java/hello/HelloWorld.java" 2>/dev/null)
fi
if [ -f "$PROJECT_DIR/src/main/java/hello/Greeter.java" ]; then
    GR_CONTENT=$(cat "$PROJECT_DIR/src/main/java/hello/Greeter.java" 2>/dev/null)
fi

# Try building the project
BUILD_SUCCESS="false"
BUILD_OUTPUT=""
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    BUILD_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile 2>&1)
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
fi

# Check class files
CLASS_EXISTS="false"
if [ -f "$PROJECT_DIR/target/classes/hello/HelloWorld.class" ]; then
    CLASS_EXISTS="true"
fi

# Escape content for JSON
POM_ESCAPED=$(echo "$POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
HW_ESCAPED=$(echo "$HW_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
GR_ESCAPED=$(echo "$GR_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BUILD_ESCAPED=$(echo "$BUILD_OUTPUT" | tail -20 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "pom_content": $POM_ESCAPED,
    "helloworld_content": $HW_ESCAPED,
    "greeter_content": $GR_ESCAPED,
    "build_success": $BUILD_SUCCESS,
    "class_exists": $CLASS_EXISTS,
    "build_output": $BUILD_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
