#!/bin/bash
echo "=== Exporting modernize_java_syntax result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/legacy-modernize"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Run tests to ensure functionality preserved
echo "Running tests..."
cd "$PROJECT_DIR"
COMPILE_SUCCESS="false"
TEST_SUCCESS="false"

# Clean compilation check
if JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean compile -q; then
    COMPILE_SUCCESS="true"
fi

# Test execution
if JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -q; then
    TEST_SUCCESS="true"
fi

# 2. Read file contents for pattern analysis
DP_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/legacy/DataProcessor.java" 2>/dev/null)
FH_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/legacy/FileHandler.java" 2>/dev/null)
ES_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/legacy/EventSystem.java" 2>/dev/null)
CP_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/legacy/ConfigParser.java" 2>/dev/null)
RG_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/legacy/ReportGenerator.java" 2>/dev/null)

# 3. Check for file modifications
FILES_MODIFIED="false"
CURRENT_CHECKSUMS=$(mktemp)
find "$PROJECT_DIR/src/main/java" -type f -exec md5sum {} + > "$CURRENT_CHECKSUMS"
if ! cmp -s /tmp/initial_checksums.txt "$CURRENT_CHECKSUMS"; then
    FILES_MODIFIED="true"
fi
rm "$CURRENT_CHECKSUMS"

# Escape content for JSON
DP_ESC=$(echo "$DP_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
FH_ESC=$(echo "$FH_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
ES_ESC=$(echo "$ES_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
CP_ESC=$(echo "$CP_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
RG_ESC=$(echo "$RG_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

# Create JSON
RESULT_JSON=$(cat << EOF
{
    "compile_success": $COMPILE_SUCCESS,
    "test_success": $TEST_SUCCESS,
    "files_modified": $FILES_MODIFIED,
    "source_files": {
        "DataProcessor.java": $DP_ESC,
        "FileHandler.java": $FH_ESC,
        "EventSystem.java": $ES_ESC,
        "ConfigParser.java": $CP_ESC,
        "ReportGenerator.java": $RG_ESC
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"