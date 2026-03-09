#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Night Viewing Mode Result ==="

# Copy VLC configuration file
VLC_RC="/home/ga/.config/vlc/vlcrc"
OUTPUT_DIR="/tmp/task_output"
mkdir -p "$OUTPUT_DIR"

if [ -f "$VLC_RC" ]; then
    echo "✅ VLC config found, copying..."
    cp "$VLC_RC" /tmp/vlc_night_mode_config.txt
    
    # Extract relevant settings for quick inspection
    echo "Video adjustment settings:" > /tmp/vlc_night_mode_settings.txt
    grep -E "^(video-filter|video-splitter|brightness|gamma|hue|contrast|saturation|adjust)" "$VLC_RC" >> /tmp/vlc_night_mode_settings.txt 2>/dev/null || echo "No adjustments found" >> /tmp/vlc_night_mode_settings.txt
    
    cat /tmp/vlc_night_mode_settings.txt
else
    echo "⚠️ VLC config not found at $VLC_RC"
    echo "Config not found" > /tmp/vlc_night_mode_config.txt
fi

# Take screenshot of VLC with adjustments applied (if still running)
if is_vlc_running; then
    echo "Capturing screenshot of VLC with night mode adjustments..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
        sleep 1
        
        # Take screenshot of the video window
        import -window root "$OUTPUT_DIR/vlc_night_mode_screenshot.png" 2>/dev/null || {
            echo "Screenshot capture failed, continuing..."
        }
    fi
    
    # Close VLC gracefully
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_night_mode_completed.txt
echo "Night viewing mode configuration task completed" >> /tmp/vlc_night_mode_completed.txt

# Create JSON summary
cat > /tmp/vlc_night_mode_result.json <<EOF
{
    "task": "configure_night_viewing_mode",
    "config_found": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "completed_at": "$(date -Iseconds)",
    "config_path": "$VLC_RC"
}
EOF

echo "✅ Export complete"
cat /tmp/vlc_night_mode_result.json

echo "=== Export Complete ==="