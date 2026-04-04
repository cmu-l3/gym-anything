#!/bin/bash
set -e
echo "=== Exporting compare_airfoil_polars results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# 2. Check project file status
PROJECT_FILE="/home/ga/Documents/projects/airfoil_comparison.wpa"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
CONTAINS_0012="false"
CONTAINS_4412="false"
CONTAINS_POLAR="false"
CONTAINS_REYNOLDS="false"
POLAR_COUNT=0

if [ -f "$PROJECT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$PROJECT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$PROJECT_FILE" 2>/dev/null || echo "0")

    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # 3. Analyze file content (QBlade .wpa files are text/XML-based)
    # Check for Airfoils
    if grep -qi "0012" "$PROJECT_FILE"; then CONTAINS_0012="true"; fi
    if grep -qi "4412" "$PROJECT_FILE"; then CONTAINS_4412="true"; fi

    # Check for Polar data structures (look for 'CPolar', 'polar', or specific data blocks)
    if grep -qiE "polar|CPolar|OpPoint" "$PROJECT_FILE"; then
        CONTAINS_POLAR="true"
    fi

    # Check for Reynolds number 500,000
    if grep -qE "500000|5\.0e5|5e5" "$PROJECT_FILE"; then
        CONTAINS_REYNOLDS="true"
    fi

    # Count occurrences of polars (rough estimate of distinct analyses)
    # QBlade often labels polars with "T1_..." or "polar" sections
    POLAR_COUNT=$(grep -ciE "polar|CPolar" "$PROJECT_FILE" || echo "0")
fi

# 4. Create JSON result
# Use temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_path": "$PROJECT_FILE",
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "contains_0012": $CONTAINS_0012,
    "contains_4412": $CONTAINS_4412,
    "contains_polar_data": $CONTAINS_POLAR,
    "contains_reynolds": $CONTAINS_REYNOLDS,
    "polar_reference_count": $POLAR_COUNT,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="