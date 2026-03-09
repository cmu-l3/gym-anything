#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Customize Subtitle Appearance Result ==="

# Close VLC to ensure config is written to disk
if is_vlc_running; then
    echo "Closing VLC to save configuration..."
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

# Give VLC time to write config
sleep 1

# Copy VLC config file for verification
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_CONFIG" ]; then
    echo "✅ VLC config found, copying for verification"
    cp "$VLC_CONFIG" /tmp/vlc_subtitle_appearance_config.txt
    
    # Show relevant subtitle settings in log for debugging
    echo "Subtitle-related settings in config:"
    grep -E "freetype|subtitle|sub-" "$VLC_CONFIG" || echo "No subtitle settings found"
else
    echo "⚠️ WARNING: VLC config not found at $VLC_CONFIG"
    touch /tmp/vlc_subtitle_appearance_config.txt
fi

# Also check alternate VLC config locations
VLC_CONFIG_DIR="/home/ga/.config/vlc"
if [ -d "$VLC_CONFIG_DIR" ]; then
    # Look for any Qt interface config that might have settings
    find "$VLC_CONFIG_DIR" -type f -name "*.conf" 2>/dev/null | while read conf_file; do
        if [ -f "$conf_file" ]; then
            echo "Found additional config: $conf_file"
            cat "$conf_file" >> /tmp/vlc_subtitle_appearance_config.txt
        fi
    done
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_subtitle_appearance_completed.txt
echo "Subtitle appearance customization task completed" >> /tmp/vlc_subtitle_appearance_completed.txt

echo "=== Export Complete ==="