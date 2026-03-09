#!/bin/bash
echo "=== Exporting create_maven_project result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/gs-maven"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check project structure
PROJECT_EXISTS="false"
POM_EXISTS="false"
HELLOWORLD_EXISTS="false"
GREETER_EXISTS="false"
BUILD_SUCCESS="false"

POM_CONTENT=""
HELLOWORLD_CONTENT=""
GREETER_CONTENT=""

if [ -d "$PROJECT_DIR" ]; then
    PROJECT_EXISTS="true"
fi

if [ -f "$PROJECT_DIR/pom.xml" ]; then
    POM_EXISTS="true"
    POM_CONTENT=$(cat "$PROJECT_DIR/pom.xml" 2>/dev/null | head -100)
fi

if [ -f "$PROJECT_DIR/src/main/java/hello/HelloWorld.java" ]; then
    HELLOWORLD_EXISTS="true"
    HELLOWORLD_CONTENT=$(cat "$PROJECT_DIR/src/main/java/hello/HelloWorld.java" 2>/dev/null)
fi

if [ -f "$PROJECT_DIR/src/main/java/hello/Greeter.java" ]; then
    GREETER_EXISTS="true"
    GREETER_CONTENT=$(cat "$PROJECT_DIR/src/main/java/hello/Greeter.java" 2>/dev/null)
fi

# Check if agent successfully built the project (DO NOT run build ourselves!)
# The agent should have triggered the build through Eclipse - we only verify the result
if [ -f "$PROJECT_DIR/target/classes/hello/HelloWorld.class" ]; then
    BUILD_SUCCESS="true"
fi

# Also check for Greeter class file
GREETER_COMPILED="false"
if [ -f "$PROJECT_DIR/target/classes/hello/Greeter.class" ]; then
    GREETER_COMPILED="true"
fi

# Escape content for JSON
POM_ESCAPED=$(echo "$POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
HW_ESCAPED=$(echo "$HELLOWORLD_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
GR_ESCAPED=$(echo "$GREETER_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Write result JSON
RESULT_JSON=$(cat << EOF
{
    "project_exists": $PROJECT_EXISTS,
    "pom_exists": $POM_EXISTS,
    "helloworld_exists": $HELLOWORLD_EXISTS,
    "greeter_exists": $GREETER_EXISTS,
    "build_success": $BUILD_SUCCESS,
    "pom_content": $POM_ESCAPED,
    "helloworld_content": $HW_ESCAPED,
    "greeter_content": $GR_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
