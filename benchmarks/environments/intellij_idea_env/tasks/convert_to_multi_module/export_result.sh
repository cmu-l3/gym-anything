#!/bin/bash
echo "=== Exporting convert_to_multi_module result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/java-library"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Read root pom.xml
ROOT_POM_CONTENT=""
[ -f "$PROJECT_DIR/pom.xml" ] && ROOT_POM_CONTENT=$(cat "$PROJECT_DIR/pom.xml")

# Check module pom.xml files exist
MATH_POM_EXISTS="false"
STRINGS_POM_EXISTS="false"
COLLECTIONS_POM_EXISTS="false"
[ -f "$PROJECT_DIR/math/pom.xml" ] && MATH_POM_EXISTS="true"
[ -f "$PROJECT_DIR/strings/pom.xml" ] && STRINGS_POM_EXISTS="true"
[ -f "$PROJECT_DIR/collections/pom.xml" ] && COLLECTIONS_POM_EXISTS="true"

MATH_POM_CONTENT=""
STRINGS_POM_CONTENT=""
COLLECTIONS_POM_CONTENT=""
[ -f "$PROJECT_DIR/math/pom.xml" ] && MATH_POM_CONTENT=$(cat "$PROJECT_DIR/math/pom.xml")
[ -f "$PROJECT_DIR/strings/pom.xml" ] && STRINGS_POM_CONTENT=$(cat "$PROJECT_DIR/strings/pom.xml")
[ -f "$PROJECT_DIR/collections/pom.xml" ] && COLLECTIONS_POM_CONTENT=$(cat "$PROJECT_DIR/collections/pom.xml")

# Run full multi-module build
BUILD_OUTPUT=$(su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn -q clean install -f '$PROJECT_DIR/pom.xml' 2>&1" || true)
BUILD_EXIT=$?
BUILD_SUCCESS="false"
[ $BUILD_EXIT -eq 0 ] && BUILD_SUCCESS="true"

# Count total tests passing across all modules
TOTAL_TESTS=0
TOTAL_FAILURES=0
for surefire_dir in "$PROJECT_DIR"/*/target/surefire-reports "$PROJECT_DIR/target/surefire-reports"; do
    [ -d "$surefire_dir" ] || continue
    for xml in "$surefire_dir"/TEST-*.xml; do
        [ -f "$xml" ] || continue
        run=$(grep -o 'tests="[0-9]*"' "$xml" | grep -o '[0-9]*' | head -1)
        fail=$(grep -o 'failures="[0-9]*"' "$xml" | grep -o '[0-9]*' | head -1)
        TOTAL_TESTS=$((TOTAL_TESTS + ${run:-0}))
        TOTAL_FAILURES=$((TOTAL_FAILURES + ${fail:-0}))
    done
done

# Checksum comparison
CURRENT_ROOT_CHECKSUM=$(md5sum "$PROJECT_DIR/pom.xml" 2>/dev/null | cut -d' ' -f1 || echo "")
INITIAL_ROOT_CHECKSUM=$(cat /tmp/initial_root_pom_checksum.txt 2>/dev/null | cut -d' ' -f1 || echo "")
ROOT_POM_MODIFIED="false"
[ "$CURRENT_ROOT_CHECKSUM" != "$INITIAL_ROOT_CHECKSUM" ] && ROOT_POM_MODIFIED="true"

# JSON-escape
ROOT_POM_ESCAPED=$(echo "$ROOT_POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
MATH_POM_ESCAPED=$(echo "$MATH_POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
STRINGS_POM_ESCAPED=$(echo "$STRINGS_POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
COLLECTIONS_POM_ESCAPED=$(echo "$COLLECTIONS_POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BUILD_ESCAPED=$(echo "$BUILD_OUTPUT" | tail -40 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "root_pom_content": $ROOT_POM_ESCAPED,
    "root_pom_modified": $ROOT_POM_MODIFIED,
    "math_pom_exists": $MATH_POM_EXISTS,
    "strings_pom_exists": $STRINGS_POM_EXISTS,
    "collections_pom_exists": $COLLECTIONS_POM_EXISTS,
    "math_pom_content": $MATH_POM_ESCAPED,
    "strings_pom_content": $STRINGS_POM_ESCAPED,
    "collections_pom_content": $COLLECTIONS_POM_ESCAPED,
    "build_success": $BUILD_SUCCESS,
    "total_tests": $TOTAL_TESTS,
    "total_failures": $TOTAL_FAILURES,
    "build_output": $BUILD_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "math_pom=$MATH_POM_EXISTS strings_pom=$STRINGS_POM_EXISTS collections_pom=$COLLECTIONS_POM_EXISTS build_success=$BUILD_SUCCESS"
echo "=== Export complete ==="
