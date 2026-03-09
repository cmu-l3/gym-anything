#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Screenshot Hotkey Result ==="

# Close VLC gracefully to ensure configuration is saved
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    echo "Closing VLC to save configuration..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 3
    
    # Force close if still running
    if is_vlc_running; then
        echo "VLC still running, force closing..."
        kill_vlc ga
        sleep 1
    fi
else
    echo "VLC already closed"
fi

# Copy VLC configuration file for verification
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "✅ VLC config file found, copying for verification..."
    cp "$VLC_RC" /tmp/vlc_hotkey_config.txt
    
    # Extract hotkey settings for logging
    echo "Current hotkey settings:"
    grep -E "^(key-snapshot|global-key-snapshot)=" "$VLC_RC" || echo "No snapshot hotkey found"
    
    # Also extract to JSON for easier parsing
    SNAPSHOT_HOTKEY=$(grep "^key-snapshot=" "$VLC_RC" | cut -d= -f2 | head -1 || echo "")
    GLOBAL_SNAPSHOT_HOTKEY=$(grep "^global-key-snapshot=" "$VLC_RC" | cut -d= -f2 | head -1 || echo "")
    
    cat > /tmp/vlc_hotkey_result.json <<EOF
{
    "key-snapshot": "$SNAPSHOT_HOTKEY",
    "global-key-snapshot": "$GLOBAL_SNAPSHOT_HOTKEY",
    "config_path": "$VLC_RC"
}
EOF
    
    echo "✅ Hotkey configuration exported"
    cat /tmp/vlc_hotkey_result.json
else
    echo "⚠️ VLC config file not found at $VLC_RC"
    
    # Create empty result
    cat > /tmp/vlc_hotkey_result.json <<EOF
{
    "key-snapshot": "",
    "global-key-snapshot": "",
    "config_path": "",
    "error": "Config file not found"
}
EOF
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_hotkey_completed.txt
echo "Screenshot hotkey configuration task completed" >> /tmp/vlc_hotkey_completed.txt

echo "=== Export Complete ==="