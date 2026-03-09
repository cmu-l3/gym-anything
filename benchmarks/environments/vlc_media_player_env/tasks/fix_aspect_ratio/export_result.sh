#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Aspect Ratio Result ==="

# VLC stores aspect ratio in its config file
VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_RC="$VLC_CONFIG_DIR/vlcrc"

# Check if config exists
if [ -f "$VLC_RC" ]; then
    echo "✅ VLC config found: $VLC_RC"
    
    # Copy VLC config to /tmp for verification
    cp "$VLC_RC" /tmp/vlc_aspect_config.txt
    
    # Extract aspect ratio setting for logging
    if grep -q "aspect-ratio=" "$VLC_RC"; then
        ASPECT_SETTING=$(grep "^aspect-ratio=" "$VLC_RC" | head -1)
        echo "Aspect ratio setting found: $ASPECT_SETTING"
    else
        echo "⚠️ No aspect-ratio setting found in config"
    fi
    
    # Also check for related settings
    grep -E "^(aspect-ratio|monitor-par|crop)=" "$VLC_RC" > /tmp/vlc_aspect_settings.txt 2>/dev/null || echo "No aspect settings found" > /tmp/vlc_aspect_settings.txt
    
    echo "Aspect-related settings:"
    cat /tmp/vlc_aspect_settings.txt
else
    echo "⚠️ VLC config file not found at $VLC_RC"
    echo "not_found" > /tmp/vlc_aspect_config.txt
fi

# Export VLC cache and preferences
if [ -d "/home/ga/.cache/vlc" ]; then
    mkdir -p /tmp/vlc_cache_export
    cp -r /home/ga/.cache/vlc/* /tmp/vlc_cache_export/ 2>/dev/null || true
fi

# Check recent files list (to confirm video was opened)
if [ -f "$VLC_RC" ]; then
    grep -E "recent|list" "$VLC_RC" | grep -i "old_family_video" > /tmp/vlc_recent_check.txt 2>/dev/null || echo "not_in_recent" > /tmp/vlc_recent_check.txt
fi

# Close VLC
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

# Create completion marker
echo "$(date -u +"%Y-%m-%d %H:%M:%S UTC")" > /tmp/vlc_aspect_completed.txt
echo "Task: fix_aspect_ratio@1" >> /tmp/vlc_aspect_completed.txt
echo "Video: /home/ga/Videos/old_family_video.mp4" >> /tmp/vlc_aspect_completed.txt
echo "Expected aspect ratio: 4:3" >> /tmp/vlc_aspect_completed.txt

# Export task logs if they exist
if [ -d "/tmp/vlc_task_logs" ]; then
    cp -r /tmp/vlc_task_logs /tmp/vlc_task_logs_export 2>/dev/null || true
fi

echo "=== Export Complete ==="
echo "Exported files:"
ls -lh /tmp/vlc_aspect_* /tmp/vlc_recent_check.txt 2>/dev/null || true