#!/bin/bash
echo "=== Exporting cytc_alignment_curation_trimming results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
WORK_DIR="/home/ga/UGENE_Data/curated_alignment"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Initialize variables
INITIAL_ALN_EXISTS="false"
INITIAL_ALN_MTIME=0
CURATED_ALN_EXISTS="false"
CURATED_ALN_MTIME=0
REPORT_EXISTS="false"
REPORT_MTIME=0

# Clean target tmp files just in case
rm -f /tmp/initial_cytochrome.aln /tmp/curated_cytochrome.aln /tmp/curation_report.txt 2>/dev/null

# Copy files securely for verifier
if [ -f "$WORK_DIR/initial_cytochrome.aln" ]; then
    INITIAL_ALN_EXISTS="true"
    INITIAL_ALN_MTIME=$(stat -c %Y "$WORK_DIR/initial_cytochrome.aln" 2>/dev/null || echo "0")
    cp "$WORK_DIR/initial_cytochrome.aln" "/tmp/initial_cytochrome.aln"
    chmod 666 "/tmp/initial_cytochrome.aln"
fi

if [ -f "$WORK_DIR/curated_cytochrome.aln" ]; then
    CURATED_ALN_EXISTS="true"
    CURATED_ALN_MTIME=$(stat -c %Y "$WORK_DIR/curated_cytochrome.aln" 2>/dev/null || echo "0")
    cp "$WORK_DIR/curated_cytochrome.aln" "/tmp/curated_cytochrome.aln"
    chmod 666 "/tmp/curated_cytochrome.aln"
fi

if [ -f "$WORK_DIR/curation_report.txt" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$WORK_DIR/curation_report.txt" 2>/dev/null || echo "0")
    cp "$WORK_DIR/curation_report.txt" "/tmp/curation_report.txt"
    chmod 666 "/tmp/curation_report.txt"
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "ugene" > /dev/null && echo "true" || echo "false")

# Create JSON metadata result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "app_running": $APP_RUNNING,
    "initial_aln_exists": $INITIAL_ALN_EXISTS,
    "initial_aln_mtime": $INITIAL_ALN_MTIME,
    "curated_aln_exists": $CURATED_ALN_EXISTS,
    "curated_aln_mtime": $CURATED_ALN_MTIME,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="