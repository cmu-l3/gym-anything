#!/bin/bash
echo "=== Exporting Kidney Volume Ratio Analysis Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

RESULT_FILE="/tmp/kidney_task_result.json"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
REPORT_FILE="$EXPORT_DIR/kidney_analysis.txt"
GT_FILE="/var/lib/slicer/ground_truth/kidney_volume_gt.json"

# Get timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Check if report file exists
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_TIMESTAMP="0"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null | head -20)
    REPORT_TIMESTAMP=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
fi

# Check if report was created after task start (anti-gaming)
REPORT_CREATED_AFTER_START="false"
if [ "$REPORT_TIMESTAMP" -gt "$TASK_START" ]; then
    REPORT_CREATED_AFTER_START="true"
fi

# Parse report content - extract values
RIGHT_VOLUME=""
LEFT_VOLUME=""
RATIO=""
RECOMMENDATION=""

if [ "$REPORT_EXISTS" = "true" ]; then
    # Extract right kidney volume (flexible parsing)
    RIGHT_VOLUME=$(grep -i "right" "$REPORT_FILE" 2>/dev/null | grep -oE '[0-9]+\.?[0-9]*' | head -1)
    
    # Extract left kidney volume
    LEFT_VOLUME=$(grep -i "left" "$REPORT_FILE" 2>/dev/null | grep -oE '[0-9]+\.?[0-9]*' | head -1)
    
    # Extract ratio
    RATIO=$(grep -i "ratio" "$REPORT_FILE" 2>/dev/null | grep -oE '[0-9]+\.?[0-9]*' | head -1)
    
    # Extract recommendation (LEFT or RIGHT)
    RECOMMENDATION=$(grep -i "preserve" "$REPORT_FILE" 2>/dev/null | grep -ioE '(left|right)' | head -1 | tr '[:lower:]' '[:upper:]')
fi

# Load ground truth values
GT_RIGHT=""
GT_LEFT=""
GT_RATIO=""
GT_PRESERVE=""

if [ -f "$GT_FILE" ]; then
    GT_RIGHT=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['right_kidney_volume_ml'])" 2>/dev/null || echo "")
    GT_LEFT=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['left_kidney_volume_ml'])" 2>/dev/null || echo "")
    GT_RATIO=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['volume_ratio'])" 2>/dev/null || echo "")
    GT_PRESERVE=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['preserve_recommendation'])" 2>/dev/null || echo "")
fi

# Check for segment statistics computation
STATS_COMPUTED="false"
STATS_TABLE_EXISTS="false"

if [ "$SLICER_RUNNING" = "true" ]; then
    # Try to check Slicer state for statistics table
    STATS_CHECK_SCRIPT="/tmp/check_stats.py"
    cat > "$STATS_CHECK_SCRIPT" << 'PYEOF'
import slicer
tables = slicer.util.getNodesByClass('vtkMRMLTableNode')
stats_tables = [t for t in tables if 'statistics' in t.GetName().lower() or 'segment' in t.GetName().lower()]
if stats_tables:
    print("STATS_FOUND")
    # Try to extract values from the table
    for table in stats_tables:
        if table.GetNumberOfRows() > 0:
            print(f"TABLE:{table.GetName()}")
            for col in range(table.GetNumberOfColumns()):
                col_name = table.GetColumnName(col)
                print(f"COL:{col_name}")
else:
    print("NO_STATS")
PYEOF

    STATS_OUTPUT=$(sudo -u ga DISPLAY=:1 timeout 10 /opt/Slicer/Slicer --python-script "$STATS_CHECK_SCRIPT" --no-main-window 2>/dev/null || echo "")
    
    if echo "$STATS_OUTPUT" | grep -q "STATS_FOUND"; then
        STATS_COMPUTED="true"
        STATS_TABLE_EXISTS="true"
    fi
    
    rm -f "$STATS_CHECK_SCRIPT" 2>/dev/null || true
fi

# Also check if any measurements file was created by Slicer
SLICER_MEASUREMENTS=""
if [ -d "$EXPORT_DIR" ]; then
    RECENT_FILES=$(find "$EXPORT_DIR" -type f -newer /tmp/task_start_time.txt 2>/dev/null | head -5)
    if [ -n "$RECENT_FILES" ]; then
        SLICER_MEASUREMENTS="$RECENT_FILES"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_running": $SLICER_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_created_after_start": $REPORT_CREATED_AFTER_START,
    "report_timestamp": $REPORT_TIMESTAMP,
    "right_volume_reported": "$RIGHT_VOLUME",
    "left_volume_reported": "$LEFT_VOLUME",
    "ratio_reported": "$RATIO",
    "recommendation_reported": "$RECOMMENDATION",
    "gt_right_volume": "$GT_RIGHT",
    "gt_left_volume": "$GT_LEFT",
    "gt_ratio": "$GT_RATIO",
    "gt_preserve": "$GT_PRESERVE",
    "stats_computed": $STATS_COMPUTED,
    "stats_table_exists": $STATS_TABLE_EXISTS,
    "report_content": $(echo "$REPORT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
}
EOF

# Move to final location with permission handling
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Results Exported ==="
echo "Result file: $RESULT_FILE"
cat "$RESULT_FILE"
echo ""

# Display report if it exists
if [ "$REPORT_EXISTS" = "true" ]; then
    echo ""
    echo "=== Agent's Report ==="
    cat "$REPORT_FILE"
    echo ""
fi

echo "=== Export Complete ==="