#!/bin/bash
echo "=== Exporting fix_build_errors result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/gs-maven-broken"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check project structure
POM_EXISTS="false"
HAS_JODATIME_DEP="false"
BUILD_SUCCESS="false"
POM_CONTENT=""

if [ -f "$PROJECT_DIR/pom.xml" ]; then
    POM_EXISTS="true"
    POM_CONTENT=$(cat "$PROJECT_DIR/pom.xml" 2>/dev/null)

    # Check if joda-time dependency was added
    if echo "$POM_CONTENT" | grep -qi "joda-time"; then
        HAS_JODATIME_DEP="true"
    fi
fi

# Check if agent successfully built the project (DO NOT run build ourselves!)
# The agent should have triggered the build - we only verify the result
if [ -f "$PROJECT_DIR/target/classes/hello/HelloWorld.class" ]; then
    BUILD_SUCCESS="true"
fi

# Check for compile errors in Eclipse's .markers file (indicates build state)
MARKERS_FILE="$PROJECT_DIR/.metadata/.plugins/org.eclipse.core.resources/.markers"
if [ -f "$MARKERS_FILE" ]; then
    if ! grep -q "jdt.core.problem" "$MARKERS_FILE" 2>/dev/null; then
        # No Java problems found in markers = build likely succeeded
        BUILD_SUCCESS="true"
    fi
fi

MAVEN_OUTPUT=""

# Escape content for JSON
POM_ESCAPED=$(echo "$POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
MAVEN_ESCAPED=$(echo "$MAVEN_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Write result JSON
RESULT_JSON=$(cat << EOF
{
    "pom_exists": $POM_EXISTS,
    "has_jodatime_dependency": $HAS_JODATIME_DEP,
    "build_success": $BUILD_SUCCESS,
    "pom_content": $POM_ESCAPED,
    "maven_output": $MAVEN_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
