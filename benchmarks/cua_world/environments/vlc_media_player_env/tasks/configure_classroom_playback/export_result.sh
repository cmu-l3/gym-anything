#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Classroom Playback Result ==="

# Give VLC time to save any pending config changes
sleep 1

# Close VLC to ensure all settings are written to vlcrc
if is_vlc_running; then
    echo "Closing VLC to save configuration..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Close via Ctrl+Q
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
        sleep 1
    fi
fi

echo "VLC closed, configuration should be saved"

# Copy VLC configuration file
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "✅ VLC configuration file found"
    cp "$VLC_RC" /tmp/vlc_classroom_config.txt
    
    # Also create a JSON with parsed key settings for easier verification
    cat > /tmp/vlc_classroom_config_summary.json <<EOF
{
    "config_file_exists": true,
    "timestamp": "$(date -Iseconds)",
    "subtitle_settings": {
        "fontsize": "$(grep '^freetype-fontsize=' "$VLC_RC" | cut -d= -f2 || echo '0')",
        "text_scale": "$(grep '^sub-text-scale=' "$VLC_RC" | cut -d= -f2 || echo '100')",
        "bold": "$(grep '^freetype-bold=' "$VLC_RC" | cut -d= -f2 || echo '0')"
    },
    "audio_settings": {
        "gain": "$(grep '^audio-gain=' "$VLC_RC" | cut -d= -f2 || echo '0.0')",
        "normalization": "$(grep '^norm-max-level=' "$VLC_RC" | cut -d= -f2 || echo '0.0')",
        "replay_gain": "$(grep '^audio-replay-gain-mode=' "$VLC_RC" | cut -d= -f2 || echo 'none')"
    },
    "video_settings": {
        "hw_accel": "$(grep '^avcodec-hw=' "$VLC_RC" | cut -d= -f2 || echo 'any')"
    }
}
EOF
    
    echo "✅ Configuration summary created"
    cat /tmp/vlc_classroom_config_summary.json
    
else
    echo "⚠️ VLC configuration file not found"
    
    # Create empty result
    cat > /tmp/vlc_classroom_config_summary.json <<EOF
{
    "config_file_exists": false,
    "error": "vlcrc not found"
}
EOF
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_classroom_completed.txt
echo "Classroom playback configuration task completed" >> /tmp/vlc_classroom_completed.txt

echo "=== Export Complete ==="