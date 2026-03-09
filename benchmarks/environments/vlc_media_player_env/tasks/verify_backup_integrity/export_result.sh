#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Backup Integrity Result ==="

# Check for verification report
REPORT_PATH="/home/ga/Documents/backup_verification_report.txt"

if [ -f "$REPORT_PATH" ]; then
    echo "✅ Verification report found: $REPORT_PATH"
    cp "$REPORT_PATH" /tmp/vlc_backup_verification_report.txt
    echo "Report contents:"
    echo "----------------------------------------"
    cat "$REPORT_PATH"
    echo "----------------------------------------"
else
    echo "⚠️ Verification report not found at expected location"
    
    # Look for any recently created text files in Documents
    RECENT_TXT=$(find /home/ga/Documents -name "*.txt" -type f -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_TXT" ]; then
        echo "Found recent text file: $RECENT_TXT"
        cp "$RECENT_TXT" /tmp/vlc_backup_verification_report.txt
    else
        # Create empty report to indicate task was attempted but report not created
        echo "No verification report created" > /tmp/vlc_backup_verification_report.txt
    fi
fi

# Copy backup file for independent verification
BACKUP_FILE="/home/ga/Videos/backup/important_recording.mp4"
if [ -f "$BACKUP_FILE" ]; then
    echo "Copying backup file for verification..."
    cp "$BACKUP_FILE" /tmp/vlc_backup_file.mp4
else
    echo "⚠️ Backup file not found"
fi

# Copy original file for independent verification
ORIGINAL_FILE="/home/ga/Videos/original/important_recording.mp4"
if [ -f "$ORIGINAL_FILE" ]; then
    echo "Copying original file for verification..."
    cp "$ORIGINAL_FILE" /tmp/vlc_original_file.mp4
else
    echo "⚠️ Original file not found"
fi

# Close VLC if running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_backup_integrity_completed.txt
echo "Backup integrity verification task completed" >> /tmp/vlc_backup_integrity_completed.txt

echo "=== Export Complete ==="