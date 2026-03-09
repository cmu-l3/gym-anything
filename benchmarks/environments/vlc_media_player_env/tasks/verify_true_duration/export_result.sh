#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

TASK_NAME="verify_true_duration"
LOG="/tmp/${TASK_NAME}_export.log"

echo "=== Exporting results for ${TASK_NAME} ===" | tee "$LOG"

# Check if duration report exists
REPORT_FILE="/home/ga/Documents/duration_report.txt"

if [ -f "$REPORT_FILE" ]; then
    echo "✅ Duration report found" | tee -a "$LOG"
    cp "$REPORT_FILE" /tmp/vlc_duration_report.txt
    echo "Report contents:" | tee -a "$LOG"
    cat "$REPORT_FILE" | tee -a "$LOG"
else
    echo "⚠️ Duration report not found at $REPORT_FILE" | tee -a "$LOG"
    # Create empty file so verification doesn't fail completely
    touch /tmp/vlc_duration_report.txt
fi

# Copy the test video file for ground truth verification
if [ -f /home/ga/Videos/interview_recording.mp4 ]; then
    echo "Copying test video for verification..." | tee -a "$LOG"
    cp /home/ga/Videos/interview_recording.mp4 /tmp/vlc_test_video.mp4
    echo "✓ Test video copied" | tee -a "$LOG"
else
    echo "⚠️ Test video not found" | tee -a "$LOG"
fi

# Copy VLC logs if they exist for debugging
if [ -f /tmp/vlc_duration_task.log ]; then
    cp /tmp/vlc_duration_task.log /tmp/vlc_duration_vlc.log 2>&1 | tee -a "$LOG"
fi

# Export VLC config for analysis (optional)
if [ -f /home/ga/.config/vlc/vlcrc ]; then
    cp /home/ga/.config/vlc/vlcrc /tmp/vlc_duration_config.txt 2>&1 | tee -a "$LOG"
fi

# Close VLC if running
if is_vlc_running; then
    echo "Closing VLC..." | tee -a "$LOG"
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..." | tee -a "$LOG"
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_duration_completed.txt
echo "Task: ${TASK_NAME}" >> /tmp/vlc_duration_completed.txt
echo "Status: Export completed" >> /tmp/vlc_duration_completed.txt

echo "[$(date)] Export complete!" | tee -a "$LOG"