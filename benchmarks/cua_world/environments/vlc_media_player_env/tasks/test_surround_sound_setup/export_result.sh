#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Surround Sound Test Result ==="

# Copy VLC config file for verification
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlc_surround_config.txt
    echo "✅ VLC config copied"
    
    # Show relevant audio settings
    echo "Audio settings in config:"
    grep -E "^(aout=|audio-channels=|alsa|pulse)" "$VLC_RC" || echo "  (no explicit audio settings)"
else
    echo "⚠️ VLC config not found"
    touch /tmp/vlc_surround_config.txt
fi

# Copy audio configuration report if exists
REPORT_FILE="/home/ga/Documents/audio_config_report.txt"
REPORT_FOUND="false"

if [ -f "$REPORT_FILE" ]; then
    cp "$REPORT_FILE" /tmp/audio_config_report.txt
    echo "✅ Audio report found and copied"
    echo "Report content:"
    head -20 "$REPORT_FILE"
    REPORT_FOUND="true"
else
    echo "⚠️ Audio report not found at $REPORT_FILE"
    
    # Check for alternative locations or names
    for pattern in "audio" "surround" "report" "config" "5.1"; do
        ALT_REPORT=$(find /home/ga/Documents -type f -iname "*${pattern}*" -mmin -10 2>/dev/null | head -1)
        if [ -n "$ALT_REPORT" ] && [ -f "$ALT_REPORT" ]; then
            echo "Found alternative report: $ALT_REPORT"
            cp "$ALT_REPORT" /tmp/audio_config_report.txt
            REPORT_FOUND="true"
            break
        fi
    done
fi

if [ "$REPORT_FOUND" = "false" ]; then
    # Create empty placeholder
    touch /tmp/audio_config_report.txt
fi

# Check if test file was played - look in VLC recent items / media library
VLC_STATE_DIR="/home/ga/.local/share/vlc"
TEST_FILE_ACCESSED="false"

if [ -d "$VLC_STATE_DIR" ]; then
    # Check media library
    if [ -f "$VLC_STATE_DIR/ml.xspf" ]; then
        cp "$VLC_STATE_DIR/ml.xspf" /tmp/vlc_recent_items.xml
        
        if grep -q "surround_test" "$VLC_STATE_DIR/ml.xspf" 2>/dev/null; then
            TEST_FILE_ACCESSED="true"
            echo "✅ Test file found in VLC media library"
        fi
    fi
    
    # Check recently used
    if [ -f "$VLC_STATE_DIR/vlc-qt-interface.conf" ]; then
        if grep -q "surround_test" "$VLC_STATE_DIR/vlc-qt-interface.conf" 2>/dev/null; then
            TEST_FILE_ACCESSED="true"
            echo "✅ Test file found in VLC recent files"
        fi
    fi
fi

# Check VLC logs for test file references
if [ -f /tmp/vlc_surround_task.log ]; then
    cp /tmp/vlc_surround_task.log /tmp/vlc_surround_result.log
    
    if grep -q "surround_test" /tmp/vlc_surround_task.log 2>/dev/null; then
        TEST_FILE_ACCESSED="true"
        echo "✅ Test file referenced in VLC logs"
    fi
fi

# Close VLC gracefully
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
    fi
fi

# Create structured result metadata
cat > /tmp/vlc_surround_result.json <<EOF
{
    "config_found": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "report_found": $REPORT_FOUND,
    "test_file_accessed": $TEST_FILE_ACCESSED,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✅ Result metadata saved"
cat /tmp/vlc_surround_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_surround_completed.txt
echo "Surround sound test task completed" >> /tmp/vlc_surround_completed.txt
echo "Report found: $REPORT_FOUND" >> /tmp/vlc_surround_completed.txt
echo "Test file accessed: $TEST_FILE_ACCESSED" >> /tmp/vlc_surround_completed.txt

echo "=== Export Complete ==="