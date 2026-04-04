#!/bin/bash
echo "=== Exporting Refactor Task Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/CorporateReporting"
SOURCE_FILE="$PROJECT_DIR/src/main/java/com/corp/reporting/ReportService.java"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Capture file content
FILE_CONTENT=""
if [ -f "$SOURCE_FILE" ]; then
    FILE_CONTENT=$(cat "$SOURCE_FILE")
fi

# Attempt to compile and test using Maven (independent verification)
# We do this to check if the refactoring broke anything
MAVEN_OUTPUT=""
BUILD_SUCCESS="false"
TESTS_PASSED="false"

if [ -d "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR"
    # Run clean package to verify build and tests
    MAVEN_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean package -DskipTests=false 2>&1)
    
    if echo "$MAVEN_OUTPUT" | grep -q "BUILD SUCCESS"; then
        BUILD_SUCCESS="true"
        TESTS_PASSED="true"
    elif echo "$MAVEN_OUTPUT" | grep -q "COMPILATION ERROR"; then
        BUILD_SUCCESS="false"
    else
        # Compilation likely passed, but tests failed
        if echo "$MAVEN_OUTPUT" | grep -q "Compiling"; then
             BUILD_SUCCESS="true"
        fi
        TESTS_PASSED="false"
    fi
fi

# Escape content for JSON
CONTENT_ESCAPED=$(echo "$FILE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
MAVEN_ESCAPED=$(echo "$MAVEN_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "file_exists": $([ -f "$SOURCE_FILE" ] && echo "true" || echo "false"),
    "file_content": $CONTENT_ESCAPED,
    "build_success": $BUILD_SUCCESS,
    "tests_passed": $TESTS_PASSED,
    "maven_output": $MAVEN_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="