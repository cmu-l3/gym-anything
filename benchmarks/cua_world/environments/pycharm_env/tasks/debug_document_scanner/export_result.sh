#!/bin/bash
echo "=== Exporting debug_document_scanner Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="debug_document_scanner"
PROJECT_DIR="/home/ga/PycharmProjects/scanner_pro"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# --- Run Test Suite ---
# Capture output to check individual test passes
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TEST_THRESH_PASS="false"
TEST_CONTOUR_PASS="false"
TEST_GEOM_PASS="false"
ALL_TESTS_PASS="false"

echo "$PYTEST_OUTPUT" | grep -q "test_threshold_crash PASSED" && TEST_THRESH_PASS="true"
echo "$PYTEST_OUTPUT" | grep -q "test_contour_selection_logic PASSED" && TEST_CONTOUR_PASS="true"
echo "$PYTEST_OUTPUT" | grep -q "test_order_points PASSED" && TEST_GEOM_PASS="true"
[ $PYTEST_EXIT_CODE -eq 0 ] && ALL_TESTS_PASS="true"

# --- Static Code Analysis for Fixes ---
PROCESSOR_FILE="$PROJECT_DIR/scanner_pro/processor.py"
CONTENT=$(cat "$PROCESSOR_FILE" 2>/dev/null)

# Check Bug 1: Contour Sorting
# Look for sorted(..., contourArea, ...)
BUG1_FIXED="false"
if echo "$CONTENT" | grep -q "sorted.*contourArea"; then
    BUG1_FIXED="true"
fi

# Check Bug 2: Geometry Logic
# Look for correction of argmin/argmax logic for rect[1] and rect[3]
# Original Buggy: rect[1] = ...argmax(diff), rect[3] = ...argmin(diff)
# Correct: rect[1] = ...argmin(diff), rect[3] = ...argmax(diff)
BUG2_FIXED="false"
if echo "$CONTENT" | grep -q "rect\[1\].*argmin.*diff" && \
   echo "$CONTENT" | grep -q "rect\[3\].*argmax.*diff"; then
    BUG2_FIXED="true"
fi

# Check Bug 3: Threshold Block Size
# Look for odd number (11, 13, 15, etc) instead of 12
BUG3_FIXED="false"
if echo "$CONTENT" | grep -q "adaptiveThreshold" && \
   ! echo "$CONTENT" | grep -q ",\s*12\s*,"; then
    # Simple check: if 12 is gone from that line, likely fixed
    BUG3_FIXED="true"
fi

# --- Run Pipeline on Hidden Test Image ---
# This ensures it actually works and produces valid output
HIDDEN_INPUT="$PROJECT_DIR/data/hidden_test.jpg"
HIDDEN_OUTPUT="$PROJECT_DIR/output/scanned_hidden_test.jpg"

su - ga -c "cd '$PROJECT_DIR' && python3 main.py '$HIDDEN_INPUT' > /dev/null 2>&1"

PIPELINE_SUCCESS="false"
OUTPUT_ASPECT="0"
if [ -f "$HIDDEN_OUTPUT" ]; then
    # Check image validity and aspect ratio
    # Our receipt is 300x500 (ratio 0.6) but depends on perspective transform
    IMG_INFO=$(python3 -c "
import cv2
try:
    img = cv2.imread('$HIDDEN_OUTPUT')
    h, w = img.shape[:2]
    print(f'{w},{h}')
except:
    print('0,0')
")
    W=$(echo $IMG_INFO | cut -d, -f1)
    H=$(echo $IMG_INFO | cut -d, -f2)
    
    if [ "$W" -gt 100 ] && [ "$H" -gt 100 ]; then
        PIPELINE_SUCCESS="true"
        # Calc aspect ratio (float)
        OUTPUT_ASPECT=$(python3 -c "print(float($W)/$H)")
    fi
fi

# Create Result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "tests_passed": $ALL_TESTS_PASS,
    "test_threshold_pass": $TEST_THRESH_PASS,
    "test_contour_pass": $TEST_CONTOUR_PASS,
    "test_geom_pass": $TEST_GEOM_PASS,
    "code_fix_sort": $BUG1_FIXED,
    "code_fix_geom": $BUG2_FIXED,
    "code_fix_thresh": $BUG3_FIXED,
    "pipeline_success": $PIPELINE_SUCCESS,
    "output_aspect": $OUTPUT_ASPECT
}
EOF

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="