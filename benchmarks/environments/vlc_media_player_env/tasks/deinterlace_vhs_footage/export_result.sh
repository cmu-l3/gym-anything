#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Deinterlace VHS Footage Result ==="

# Ensure VLC has saved its configuration
VLC_RC="/home/ga/.config/vlc/vlcrc"
VLC_QT_CONF="/home/ga/.config/vlc/vlc-qt-interface.conf"

# Give VLC a moment to save settings if they were just changed
sleep 1

# Check if VLC config exists
if [ -f "$VLC_RC" ]; then
    echo "✅ VLC config found: $VLC_RC"
    
    # Check for deinterlacing settings
    if grep -q "deinterlace" "$VLC_RC"; then
        echo "✅ Deinterlacing settings detected in config"
        grep "deinterlace" "$VLC_RC" || true
    else
        echo "⚠️ No deinterlacing settings found in config"
    fi
    
    # Copy config to temp location for verification
    cp "$VLC_RC" /tmp/vlc_deinterlace_config.txt
else
    echo "⚠️ VLC config not found at $VLC_RC"
fi

# Also check Qt interface config (sometimes deinterlace settings stored here)
if [ -f "$VLC_QT_CONF" ]; then
    echo "✅ VLC Qt config found"
    if grep -q -i "deinterlace" "$VLC_QT_CONF"; then
        echo "✅ Deinterlacing settings in Qt config"
        cp "$VLC_QT_CONF" /tmp/vlc_deinterlace_qt_config.txt
    fi
fi

# Close VLC to ensure settings are persisted
if is_vlc_running; then
    echo "Closing VLC to save settings..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # If still running, force kill
    if is_vlc_running; then
        echo "VLC still running, force closing..."
        kill_vlc ga
        sleep 1
    fi
fi

# After closing, re-check config to ensure persistence
if [ -f "$VLC_RC" ]; then
    echo "Final config check after VLC close:"
    grep "deinterlace" "$VLC_RC" || echo "No deinterlace settings found"
    
    # Update the exported config with final state
    cp "$VLC_RC" /tmp/vlc_deinterlace_config.txt
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_deinterlace_completed.txt
echo "Deinterlace VHS footage task completed" >> /tmp/vlc_deinterlace_completed.txt

# Create a summary JSON for easier verification
cat > /tmp/vlc_deinterlace_summary.json <<EOF
{
    "task": "deinterlace_vhs_footage@1",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "config_file_exists": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "config_exported": $([ -f /tmp/vlc_deinterlace_config.txt ] && echo "true" || echo "false")
}
EOF

echo "✅ Configuration exported to /tmp/vlc_deinterlace_config.txt"
echo "✅ Summary saved to /tmp/vlc_deinterlace_summary.json"

cat /tmp/vlc_deinterlace_summary.json

echo "=== Export Complete ==="