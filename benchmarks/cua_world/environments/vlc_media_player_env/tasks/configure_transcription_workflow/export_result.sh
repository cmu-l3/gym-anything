#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Transcription Workflow Result ==="

VLC_RC="/home/ga/.config/vlc/vlcrc"

# Give VLC a moment to save config if preferences were just closed
sleep 2

# Check if config file exists
if [ -f "$VLC_RC" ]; then
    echo "✅ VLC config file found: $VLC_RC"
    
    # Display relevant config lines for debugging
    echo "Configuration excerpt:"
    grep -E "jump|hotkey" "$VLC_RC" 2>/dev/null || echo "No jump configuration found in grep"
    
    # Copy config to tmp for verification
    cp "$VLC_RC" /tmp/vlc_transcription_config.vlcrc
    
    # Check file size
    CONFIG_SIZE=$(stat -f%z "$VLC_RC" 2>/dev/null || stat -c%s "$VLC_RC" 2>/dev/null || echo "0")
    echo "Config file size: $CONFIG_SIZE bytes"
else
    echo "⚠️ VLC config file not found at $VLC_RC"
    
    # Try to find config in alternative locations
    for alt_path in "/home/ga/.config/vlc/vlcrc" "/home/ga/.vlc/vlcrc"; do
        if [ -f "$alt_path" ]; then
            echo "Found config at alternative location: $alt_path"
            cp "$alt_path" /tmp/vlc_transcription_config.vlcrc
            break
        fi
    done
fi

# Close VLC to ensure config is fully written
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Try graceful close first
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
        sleep 1
    fi
fi

# Wait for config to be fully written
sleep 1

# Re-copy config after VLC closed (in case it writes on exit)
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlc_transcription_config.vlcrc
    echo "✅ Final config copied after VLC close"
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_transcription_completed.txt
echo "Transcription workflow configuration task completed" >> /tmp/vlc_transcription_completed.txt

# Create summary for debugging
cat > /tmp/vlc_transcription_summary.txt << EOF
VLC Transcription Configuration Summary
========================================
Timestamp: $(date)

Configuration File: $VLC_RC
Exists: $([ -f "$VLC_RC" ] && echo "Yes" || echo "No")

Jump Configuration:
$(grep -E "jump" "$VLC_RC" 2>/dev/null || echo "No jump configuration found")

Audio File:
$(ls -lh /home/ga/workspace/interview_audio.mp3 2>/dev/null || echo "Audio file not found")
EOF

echo "✅ Summary created"
cat /tmp/vlc_transcription_summary.txt

echo "=== Export Complete ==="