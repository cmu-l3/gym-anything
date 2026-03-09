#!/bin/bash
echo "=== Exporting healthcare_record_pipeline_bugs result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/healthcare-pipeline"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run the tests and capture results
TEST_OUTPUT=$(timeout 120 su - ga -c \
    "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -f '$PROJECT_DIR/pom.xml' 2>&1" || true)
BUILD_EXIT=$?
BUILD_SUCCESS="false"
[ $BUILD_EXIT -eq 0 ] && BUILD_SUCCESS="true"

# Read surefire XML reports
SUREFIRE_DIR="$PROJECT_DIR/target/surefire-reports"
TESTS_RUN=0
TESTS_FAILED=0
TESTS_ERROR=0

if [ -d "$SUREFIRE_DIR" ]; then
    for xml in "$SUREFIRE_DIR"/TEST-*.xml; do
        [ -f "$xml" ] || continue
        run=$(grep -o 'tests="[0-9]*"' "$xml" | grep -o '[0-9]*' | head -1)
        fail=$(grep -o 'failures="[0-9]*"' "$xml" | grep -o '[0-9]*' | head -1)
        err=$(grep -o 'errors="[0-9]*"' "$xml" | grep -o '[0-9]*' | head -1)
        TESTS_RUN=$((TESTS_RUN + ${run:-0}))
        TESTS_FAILED=$((TESTS_FAILED + ${fail:-0}))
        TESTS_ERROR=$((TESTS_ERROR + ${err:-0}))
    done
fi

# Read source file content
PATIENT_SOURCE=""
REGISTRY_SOURCE=""
CODER_SOURCE=""
if [ -f "$PROJECT_DIR/src/main/java/com/healthcare/Patient.java" ]; then
    PATIENT_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/healthcare/Patient.java")
fi
if [ -f "$PROJECT_DIR/src/main/java/com/healthcare/PatientRegistry.java" ]; then
    REGISTRY_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/healthcare/PatientRegistry.java")
fi
if [ -f "$PROJECT_DIR/src/main/java/com/healthcare/DiagnosticCoder.java" ]; then
    CODER_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/healthcare/DiagnosticCoder.java")
fi

# Compute test file checksum
TEST_CHECKSUM=$(md5sum "$PROJECT_DIR/src/test/java/com/healthcare/PatientRegistryTest.java" \
    2>/dev/null | cut -d' ' -f1 || echo "")
INITIAL_TEST_CHECKSUM=$(cat /tmp/initial_test_checksum.txt 2>/dev/null | awk '{print $1}' || echo "")

# JSON-escape content
PATIENT_ESCAPED=$(echo "$PATIENT_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
REGISTRY_ESCAPED=$(echo "$REGISTRY_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
CODER_ESCAPED=$(echo "$CODER_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -40 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "build_success": $BUILD_SUCCESS,
    "tests_run": $TESTS_RUN,
    "tests_failed": $TESTS_FAILED,
    "tests_error": $TESTS_ERROR,
    "test_checksum_initial": "$INITIAL_TEST_CHECKSUM",
    "test_checksum_current": "$TEST_CHECKSUM",
    "patient_source": $PATIENT_ESCAPED,
    "registry_source": $REGISTRY_ESCAPED,
    "coder_source": $CODER_ESCAPED,
    "mvn_output": $OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "tests_run=$TESTS_RUN failures=$TESTS_FAILED errors=$TESTS_ERROR"
echo "=== Export complete ==="
