#!/bin/bash
echo "=== Exporting implement_lru_cache_mri result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/MedicalImagingSystem"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Run Verification Tests (Anti-Gaming: Run tests in constrained environment)
# We run the tests here to generate the surefire report that verifier.py will parse.
# We limit memory to 256m to force OOM if the cache is leaking.
echo "Running verification tests..."
cd "$PROJECT_DIR"

# Clean old reports
rm -rf target/surefire-reports 2>/dev/null

# Run Maven test with constrained heap
# MRISlice is ~5MB. 100 slices = 500MB.
# -Xmx256m will definitely crash if cache is not evicted.
su - ga -c "cd $PROJECT_DIR && mvn test -DargLine='-Xmx256m'" > /tmp/mvn_test_output.log 2>&1
MVN_EXIT_CODE=$?

echo "Maven exit code: $MVN_EXIT_CODE"

# 3. Collect Evidence
SOURCE_FILE="$PROJECT_DIR/src/main/java/com/medsys/imaging/MRISliceCache.java"
TEST_REPORT="$PROJECT_DIR/target/surefire-reports/TEST-com.medsys.imaging.CacheStabilityTest.xml"

# Read source content
SOURCE_CONTENT=""
if [ -f "$SOURCE_FILE" ]; then
    SOURCE_CONTENT=$(cat "$SOURCE_FILE")
fi

# Read test report content
TEST_REPORT_CONTENT=""
if [ -f "$TEST_REPORT" ]; then
    TEST_REPORT_CONTENT=$(cat "$TEST_REPORT")
fi

# Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SOURCE_MTIME=$(stat -c %Y "$SOURCE_FILE" 2>/dev/null || echo "0")

FILE_MODIFIED="false"
if [ "$SOURCE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Encode content for JSON safety using python
SOURCE_ESCAPED=$(echo "$SOURCE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
REPORT_ESCAPED=$(echo "$TEST_REPORT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "mvn_exit_code": $MVN_EXIT_CODE,
    "file_modified": $FILE_MODIFIED,
    "source_content": $SOURCE_ESCAPED,
    "test_report_content": $REPORT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="