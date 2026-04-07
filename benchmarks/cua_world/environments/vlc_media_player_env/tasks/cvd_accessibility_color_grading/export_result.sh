#!/bin/bash
# Export script for cvd_accessibility_color_grading task
set -e

echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check for existence of expected output files
CVD_BLUE_PATH="/home/ga/Videos/accessible_variants/titration_cvd_blue.mp4"
HC_BW_PATH="/home/ga/Videos/accessible_variants/titration_high_contrast_bw.mp4"
REPORT_PATH="/home/ga/Documents/remediation_report.json"

# Extract frames for programmatic CV2 analysis in the verifier
# We extract a frame at t=8s (during the RED reaction phase) from the original and both generated videos
mkdir -p /tmp/cvd_frames

if [ -f "/home/ga/Videos/chemistry_titration.mp4" ]; then
    ffmpeg -y -ss 00:00:08 -i "/home/ga/Videos/chemistry_titration.mp4" -vframes 1 /tmp/cvd_frames/orig_frame.png 2>/dev/null || true
fi

CVD_EXISTS="false"
CVD_NEW="false"
if [ -f "$CVD_BLUE_PATH" ]; then
    CVD_EXISTS="true"
    MTIME=$(stat -c %Y "$CVD_BLUE_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then CVD_NEW="true"; fi
    ffmpeg -y -ss 00:00:08 -i "$CVD_BLUE_PATH" -vframes 1 /tmp/cvd_frames/cvd_frame.png 2>/dev/null || true
fi

BW_EXISTS="false"
BW_NEW="false"
if [ -f "$HC_BW_PATH" ]; then
    BW_EXISTS="true"
    MTIME=$(stat -c %Y "$HC_BW_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then BW_NEW="true"; fi
    ffmpeg -y -ss 00:00:08 -i "$HC_BW_PATH" -vframes 1 /tmp/cvd_frames/bw_frame.png 2>/dev/null || true
fi

REPORT_EXISTS="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    cp "$REPORT_PATH" /tmp/cvd_frames/remediation_report.json 2>/dev/null || true
fi

# Create result JSON wrapper
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "cvd_blue_exists": $CVD_EXISTS,
    "cvd_blue_created_during_task": $CVD_NEW,
    "high_contrast_bw_exists": $BW_EXISTS,
    "high_contrast_bw_created_during_task": $BW_NEW,
    "report_exists": $REPORT_EXISTS
}
EOF

# Move JSON and ensure permissions
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="