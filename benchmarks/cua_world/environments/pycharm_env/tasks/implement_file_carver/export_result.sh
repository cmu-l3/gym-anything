#!/bin/bash
echo "=== Exporting implement_file_carver Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="implement_file_carver"
PROJECT_DIR="/home/ga/PycharmProjects/file_carver"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
RECOVERED_DIR="$PROJECT_DIR/recovered_files"
GROUND_TRUTH_FILE="/home/ga/.ground_truth_hashes.json"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Run Unit Tests
echo "Running unit tests..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)

# 2. Check Recovered Files
echo "Checking recovered files..."
RECOVERED_COUNT=0
MATCH_COUNT=0
MATCH_DETAILS="[]"

if [ -d "$RECOVERED_DIR" ]; then
    RECOVERED_COUNT=$(ls "$RECOVERED_DIR" | wc -l)
    
    # Calculate hashes of all recovered files
    # We don't know the filenames the agent used (likely recovered_1.jpg etc),
    # so we check if the set of recovered hashes matches the set of ground truth hashes.
    
    # Get ground truth hashes
    GT_JPG_1=$(python3 -c "import json; print(json.load(open('$GROUND_TRUTH_FILE'))['jpg_1'])")
    GT_JPG_2=$(python3 -c "import json; print(json.load(open('$GROUND_TRUTH_FILE'))['jpg_2'])")
    GT_PNG_1=$(python3 -c "import json; print(json.load(open('$GROUND_TRUTH_FILE'))['png_1'])")
    GT_PNG_2=$(python3 -c "import json; print(json.load(open('$GROUND_TRUTH_FILE'))['png_2'])")
    
    # Arrays to track found status
    FOUND_JPG_1=false
    FOUND_JPG_2=false
    FOUND_PNG_1=false
    FOUND_PNG_2=false
    
    for f in "$RECOVERED_DIR"/*; do
        if [ -f "$f" ]; then
            F_HASH=$(sha256sum "$f" | awk '{print $1}')
            if [ "$F_HASH" == "$GT_JPG_1" ]; then FOUND_JPG_1=true; fi
            if [ "$F_HASH" == "$GT_JPG_2" ]; then FOUND_JPG_2=true; fi
            if [ "$F_HASH" == "$GT_PNG_1" ]; then FOUND_PNG_1=true; fi
            if [ "$F_HASH" == "$GT_PNG_2" ]; then FOUND_PNG_2=true; fi
        fi
    done
fi

# Create result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "recovered_count": $RECOVERED_COUNT,
    "found_jpg_1": $FOUND_JPG_1,
    "found_jpg_2": $FOUND_JPG_2,
    "found_png_1": $FOUND_PNG_1,
    "found_png_2": $FOUND_PNG_2
}
EOF

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="