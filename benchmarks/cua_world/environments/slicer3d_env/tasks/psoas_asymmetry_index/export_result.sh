#!/bin/bash
echo "=== Exporting Psoas Asymmetry Task Result ==="

source /workspace/scripts/task_utils.sh

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
ELAPSED=$((TASK_END - TASK_START))

echo "Task duration: ${ELAPSED}s"

# Get case ID
CASE_ID=$(cat /tmp/amos_case_id 2>/dev/null || echo "amos_0001")
AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
REPORT_PATH="$AMOS_DIR/psoas_asymmetry_report.json"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/psoas_final.png ga
sleep 1

# ============================================================
# Check Slicer status
# ============================================================
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# ============================================================
# Check for report file
# ============================================================
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_DATA="{}"
REPORT_CREATED_DURING_TASK="false"

# Check multiple possible locations
POSSIBLE_REPORT_PATHS=(
    "$REPORT_PATH"
    "$AMOS_DIR/psoas_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/psoas_asymmetry_report.json"
    "/home/ga/psoas_asymmetry_report.json"
    "/home/ga/Documents/SlicerData/psoas_asymmetry_report.json"
)

FOUND_REPORT_PATH=""
for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        FOUND_REPORT_PATH="$path"
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        
        # Check if created during task
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
            echo "Report was created during task"
        else
            echo "WARNING: Report may have existed before task"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$REPORT_PATH" ]; then
            cp "$path" "$REPORT_PATH" 2>/dev/null || true
        fi
        break
    fi
done

# Validate and parse report JSON
if [ "$REPORT_EXISTS" = "true" ] && [ -n "$FOUND_REPORT_PATH" ]; then
    if python3 -c "import json; json.load(open('$FOUND_REPORT_PATH'))" 2>/dev/null; then
        REPORT_VALID="true"
        REPORT_DATA=$(cat "$FOUND_REPORT_PATH")
        echo "Report JSON is valid"
    else
        echo "WARNING: Report file is not valid JSON"
    fi
fi

# ============================================================
# Check for measurement markups
# ============================================================
LEFT_MARKUP_EXISTS="false"
RIGHT_MARKUP_EXISTS="false"
MARKUP_COUNT=0

# Look for any markup files that might contain psoas measurements
for markup_path in "$AMOS_DIR"/*.mrk.json "$AMOS_DIR"/*.json; do
    if [ -f "$markup_path" ]; then
        basename_lower=$(basename "$markup_path" | tr '[:upper:]' '[:lower:]')
        if echo "$basename_lower" | grep -q "left\|psoas_l\|l_psoas"; then
            LEFT_MARKUP_EXISTS="true"
            MARKUP_COUNT=$((MARKUP_COUNT + 1))
        elif echo "$basename_lower" | grep -q "right\|psoas_r\|r_psoas"; then
            RIGHT_MARKUP_EXISTS="true"
            MARKUP_COUNT=$((MARKUP_COUNT + 1))
        fi
    fi
done

echo "Markup files found: $MARKUP_COUNT"

# ============================================================
# Check for screenshots taken during task
# ============================================================
SCREENSHOT_COUNT=$(find "$AMOS_DIR" /home/ga/Documents/SlicerData/Screenshots -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)
echo "Screenshots taken during task: $SCREENSHOT_COUNT"

# ============================================================
# Copy ground truth for verifier
# ============================================================
GT_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_psoas_gt.json"
if [ -f "$GT_FILE" ]; then
    cp "$GT_FILE" /tmp/psoas_ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/psoas_ground_truth.json 2>/dev/null || true
    echo "Ground truth copied for verification"
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << RESULTEOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_VALID,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_path": "$FOUND_REPORT_PATH",
    "report_data": $REPORT_DATA,
    "left_markup_exists": $LEFT_MARKUP_EXISTS,
    "right_markup_exists": $RIGHT_MARKUP_EXISTS,
    "markup_count": $MARKUP_COUNT,
    "screenshot_count": $SCREENSHOT_COUNT,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_elapsed_seconds": $ELAPSED,
    "case_id": "$CASE_ID",
    "ground_truth_path": "/tmp/psoas_ground_truth.json",
    "initial_screenshot": "/tmp/psoas_initial.png",
    "final_screenshot": "/tmp/psoas_final.png"
}
RESULTEOF

# Move to final location
rm -f /tmp/psoas_task_result.json 2>/dev/null || sudo rm -f /tmp/psoas_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/psoas_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/psoas_task_result.json
chmod 666 /tmp/psoas_task_result.json 2>/dev/null || sudo chmod 666 /tmp/psoas_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/psoas_task_result.json
echo ""
echo "=== Export Complete ==="