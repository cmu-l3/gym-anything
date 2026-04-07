#!/bin/bash
echo "=== Exporting insulin_cpg_gc_profiling results ==="

RESULTS_DIR="/home/ga/UGENE_Data/cpg_results"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true

# Check GB file
GB_FILE="${RESULTS_DIR}/insulin_cpg_annotated.gb"
GB_EXISTS=false
GB_SIZE=0
GB_MTIME=0

if [ -f "$GB_FILE" ]; then
    GB_EXISTS=true
    GB_SIZE=$(stat -c %s "$GB_FILE" 2>/dev/null || echo "0")
    GB_MTIME=$(stat -c %Y "$GB_FILE" 2>/dev/null || echo "0")
fi

# Check Report file
REPORT_FILE="${RESULTS_DIR}/cpg_analysis_report.txt"
REPORT_EXISTS=false
REPORT_SIZE=0
REPORT_MTIME=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
fi

# Create result JSON
cat > /tmp/insulin_cpg_result.json << EOF
{
    "task_start_ts": $TASK_START,
    "gb_exists": $GB_EXISTS,
    "gb_size": $GB_SIZE,
    "gb_mtime": $GB_MTIME,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME
}
EOF

echo "Export metadata written to /tmp/insulin_cpg_result.json"
echo "=== Export complete ==="