#!/bin/bash
echo "=== Exporting resolve_maven_dependencies result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/data-processor"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Read current pom.xml
POM_CONTENT=""
[ -f "$PROJECT_DIR/pom.xml" ] && POM_CONTENT=$(cat "$PROJECT_DIR/pom.xml")

# Run tests
TEST_OUTPUT=$(su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn -q test -f '$PROJECT_DIR/pom.xml' 2>&1" || true)
BUILD_EXIT=$?
BUILD_SUCCESS="false"
[ $BUILD_EXIT -eq 0 ] && BUILD_SUCCESS="true"

# Read surefire report
SUREFIRE_DIR="$PROJECT_DIR/target/surefire-reports"
TESTS_RUN=0
TESTS_FAILED=0
if [ -d "$SUREFIRE_DIR" ]; then
    for xml in "$SUREFIRE_DIR"/TEST-*.xml; do
        [ -f "$xml" ] || continue
        run=$(grep -o 'tests="[0-9]*"' "$xml" | grep -o '[0-9]*' | head -1)
        fail=$(grep -o 'failures="[0-9]*"' "$xml" | grep -o '[0-9]*' | head -1)
        TESTS_RUN=$((TESTS_RUN + ${run:-0}))
        TESTS_FAILED=$((TESTS_FAILED + ${fail:-0}))
    done
fi

# Detect pom.xml changes via checksum comparison
CURRENT_POM_CHECKSUM=$(md5sum "$PROJECT_DIR/pom.xml" 2>/dev/null | cut -d' ' -f1 || echo "")
INITIAL_POM_CHECKSUM=$(cat /tmp/initial_pom_checksum.txt 2>/dev/null | cut -d' ' -f1 || echo "")
POM_MODIFIED="false"
[ "$CURRENT_POM_CHECKSUM" != "$INITIAL_POM_CHECKSUM" ] && POM_MODIFIED="true"

# JSON-escape
POM_ESCAPED=$(echo "$POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -30 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "pom_content": $POM_ESCAPED,
    "pom_modified": $POM_MODIFIED,
    "build_success": $BUILD_SUCCESS,
    "tests_run": $TESTS_RUN,
    "tests_failed": $TESTS_FAILED,
    "pom_checksum_initial": "$INITIAL_POM_CHECKSUM",
    "pom_checksum_current": "$CURRENT_POM_CHECKSUM",
    "mvn_output": $OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "pom_modified=$POM_MODIFIED build_success=$BUILD_SUCCESS tests=$TESTS_RUN"
echo "=== Export complete ==="
