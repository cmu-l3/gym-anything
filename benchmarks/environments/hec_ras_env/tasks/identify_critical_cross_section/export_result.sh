#!/bin/bash
echo "=== Exporting identify_critical_cross_section results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/Documents/hec_ras_results/critical_section_report.csv"
SUMMARY_PATH="/home/ga/Documents/hec_ras_results/critical_section_summary.txt"
GT_PATH="/var/lib/hec-ras/ground_truth.json"

# Check output files
REPORT_EXISTS="false"
SUMMARY_EXISTS="false"
REPORT_CREATED_DURING="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    R_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$R_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
fi

if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare export
# We will copy the files to /tmp so the verifier can read them cleanly via copy_from_env

# 1. Agent Output
cp "$REPORT_PATH" /tmp/agent_report.csv 2>/dev/null || true
cp "$SUMMARY_PATH" /tmp/agent_summary.txt 2>/dev/null || true

# 2. Ground Truth
cp "$GT_PATH" /tmp/ground_truth.json 2>/dev/null || true

# 3. Metadata JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "summary_exists": $SUMMARY_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json /tmp/agent_report.csv /tmp/agent_summary.txt /tmp/ground_truth.json 2>/dev/null || true

echo "Export complete. Files ready in /tmp for verification."