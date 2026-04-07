#!/bin/bash
echo "=== Exporting Results for debug_pcb_defect_detector ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/pcb_inspector"
RESULT_FILE="/tmp/debug_pcb_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/pcb_final.png 2>/dev/null || true

# 1. Run Tests (to verify code correctness)
echo "Running tests..."
cd "$PROJECT_DIR"
# Install project in editable mode if needed, or just set PYTHONPATH
export PYTHONPATH=$PROJECT_DIR
PYTEST_OUT=$(python3 -m pytest tests/ --tb=short 2>&1)
PYTEST_EXIT=$?

# Parse test results
TEST_UTILS_PASS=$(echo "$PYTEST_OUT" | grep "test_utils.py" | grep -c "PASSED" || true)
TEST_CORE_PASS=$(echo "$PYTEST_OUT" | grep "test_core.py" | grep -c "PASSED" || true)

# 2. Run Main Script (to generate report.json)
echo "Running main.py..."
python3 main.py > /tmp/main_run.log 2>&1
MAIN_EXIT=$?

# Read generated report
REPORT_JSON="{}"
if [ -f "report.json" ]; then
    REPORT_JSON=$(cat report.json)
fi

# 3. Code Analysis (Simple grep checks for regressions/fixes)
# Check for Mutable Default fix
MUTABLE_DEFAULT_FIXED="false"
if grep -q "def log_defect(defect_info, defect_log=None):" "$PROJECT_DIR/pcb_inspector/utils.py"; then
    MUTABLE_DEFAULT_FIXED="true"
elif grep -q "defect_log = \[\]" "$PROJECT_DIR/pcb_inspector/utils.py"; then
     # Alternate valid fix inside function
     MUTABLE_DEFAULT_FIXED="true"
fi

# Check for ROI fix (indices order)
ROI_FIXED="false"
# Correct: test_roi = test_img[y:y+h, x:x+w]
# We look for y index coming before x index in the slice
if grep -q "test_img\[y:y+h, x:x+w\]" "$PROJECT_DIR/pcb_inspector/core.py"; then
    ROI_FIXED="true"
fi

# Check for Threshold fix (> instead of <)
THRESH_FIXED="false"
if grep -q "score > " "$PROJECT_DIR/pcb_inspector/core.py"; then
    THRESH_FIXED="true"
fi

# Construct Result JSON
cat > "$RESULT_FILE" << EOF
{
    "pytest_exit_code": $PYTEST_EXIT,
    "pytest_output": "$(echo "$PYTEST_OUT" | base64 -w 0)",
    "report_json": $REPORT_JSON,
    "static_analysis": {
        "mutable_default_fixed": $MUTABLE_DEFAULT_FIXED,
        "roi_fixed": $ROI_FIXED,
        "thresh_fixed": $THRESH_FIXED
    },
    "main_exit_code": $MAIN_EXIT,
    "timestamp": $(date +%s)
}
EOF

echo "Export completed. Result saved to $RESULT_FILE"