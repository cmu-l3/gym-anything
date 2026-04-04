#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Validate Subtitle Sync Result ==="

EXPORT_LOG="/tmp/vlc_subtitle_validation_export.log"

log() {
    echo "[EXPORT] $1" | tee -a "$EXPORT_LOG"
}

# Check for validation report
REPORT_PATH="/home/ga/subtitle_validation_report.txt"

if [ -f "$REPORT_PATH" ]; then
    log "✅ Validation report found: $REPORT_PATH"
    cp "$REPORT_PATH" /tmp/vlc_subtitle_validation_report.txt
    log "Report contents:"
    cat "$REPORT_PATH" | tee -a "$EXPORT_LOG"
else
    log "⚠️ Validation report not found at expected location"
    
    # Check if report exists elsewhere in home directory
    FOUND_REPORT=$(find /home/ga -name "*subtitle*report*.txt" -o -name "*validation*.txt" -type f -mmin -15 2>/dev/null | head -1)
    
    if [ -n "$FOUND_REPORT" ]; then
        log "Found report at alternate location: $FOUND_REPORT"
        cp "$FOUND_REPORT" /tmp/vlc_subtitle_validation_report.txt
    else
        log "Creating empty report marker for verifier"
        echo "REPORT_NOT_FOUND" > /tmp/vlc_subtitle_validation_report.txt
    fi
fi

# Copy VLC config to check if subtitles were loaded
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    log "Copying VLC config for verification..."
    cp "$VLC_RC" /tmp/vlc_subtitle_validation_config.txt
    
    # Check for subtitle-related settings
    if grep -q "sub-file\|subtitle" "$VLC_RC" 2>/dev/null; then
        log "✅ Subtitle settings found in VLC config"
    else
        log "⚠️ No subtitle settings in VLC config"
    fi
else
    log "⚠️ VLC config not found"
fi

# Copy VLC log for debugging
if [ -f /tmp/vlc_subtitle_validation_task.log ]; then
    cp /tmp/vlc_subtitle_validation_task.log /tmp/vlc_subtitle_validation_vlc.log
fi

# Close VLC gracefully
if is_vlc_running; then
    log "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        log "VLC still running, force killing..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_subtitle_validation_completed.txt
echo "Subtitle validation task export completed" >> /tmp/vlc_subtitle_validation_completed.txt
log "✅ Export complete"

echo "=== Export Complete ==="