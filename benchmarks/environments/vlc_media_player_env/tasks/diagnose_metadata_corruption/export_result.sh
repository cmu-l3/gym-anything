#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Diagnose Metadata Corruption Result ==="

REPORT_PATH="/home/ga/Documents/media_diagnostics.txt"
EXPORT_DIR="/tmp/export"

mkdir -p "$EXPORT_DIR"

# Check if diagnostic report was created
if [ -f "$REPORT_PATH" ]; then
    echo "✅ Diagnostic report found: $REPORT_PATH"
    cp "$REPORT_PATH" "$EXPORT_DIR/media_diagnostics.txt"
    
    echo "--- Report Contents ---"
    cat "$REPORT_PATH"
    echo "--- End Report ---"
else
    echo "⚠️ WARNING: Diagnostic report not found at $REPORT_PATH"
    
    # Check for reports in other common locations
    ALTERNATE_LOCATIONS=(
        "/home/ga/media_diagnostics.txt"
        "/home/ga/Documents/diagnostics.txt"
        "/home/ga/Documents/report.txt"
        "/tmp/media_diagnostics.txt"
    )
    
    for alt_path in "${ALTERNATE_LOCATIONS[@]}"; do
        if [ -f "$alt_path" ]; then
            echo "Found report at alternate location: $alt_path"
            cp "$alt_path" "$EXPORT_DIR/media_diagnostics.txt"
            break
        fi
    done
fi

# Copy the corrupted video file for potential verification
if [ -f "/home/ga/Videos/corrupted/birthday_1995.avi" ]; then
    echo "Copying corrupted video file for verification..."
    # Don't copy the full video (too large), just verify it exists
    ls -lh /home/ga/Videos/corrupted/birthday_1995.avi > "$EXPORT_DIR/corrupted_video_info.txt"
fi

# Copy ground truth for verification
if [ -f "/tmp/corruption_ground_truth.txt" ]; then
    cp /tmp/corruption_ground_truth.txt "$EXPORT_DIR/"
fi

# Export any VLC logs if they exist (user might have used VLC)
if [ -f "/tmp/vlc_*.log" ]; then
    cp /tmp/vlc_*.log "$EXPORT_DIR/" 2>/dev/null || true
fi

# Export shell history to see what commands were used
if [ -f "/home/ga/.bash_history" ]; then
    tail -n 50 /home/ga/.bash_history > "$EXPORT_DIR/commands_history.txt" 2>/dev/null || true
fi

# Close VLC if running
if is_vlc_running; then
    echo "Closing VLC if open..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q 2>/dev/null || true
    sleep 1
fi

# Create completion marker
echo "$(date)" > /tmp/diagnose_corruption_completed.txt
echo "Diagnostic task completed" >> /tmp/diagnose_corruption_completed.txt

cp /tmp/diagnose_corruption_completed.txt "$EXPORT_DIR/" 2>/dev/null || true

echo "=== Export Complete ==="
echo "Exported files:"
ls -lh "$EXPORT_DIR"