#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Troubleshoot Video Output Result ==="

# Export VLC configuration file
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "✅ VLC config file found"
    cp "$VLC_RC" /tmp/vlc_output_config.txt
    
    # Extract and display video output setting
    echo "Current video output configuration:"
    grep -E "^vout=|^# vout" "$VLC_RC" || echo "No vout setting found"
    
    # Create summary
    cat > /tmp/vlc_output_summary.txt << EOF
=== VLC Video Output Configuration ===
Export Time: $(date)
Config File: $VLC_RC

Video Output Setting:
$(grep -E "^vout=" "$VLC_RC" 2>/dev/null || echo "vout=<not set>")

Full Video Section:
$(grep -A 5 "^\[video\]" "$VLC_RC" 2>/dev/null || echo "[video] section not found")
EOF
    
    cat /tmp/vlc_output_summary.txt
else
    echo "⚠️ WARNING: VLC config file not found at $VLC_RC"
    echo "Config may not have been saved"
    touch /tmp/vlc_output_config_missing.txt
fi

# Close VLC gracefully
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
        sleep 0.5
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force killing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_output_completed.txt
echo "Video output configuration task completed" >> /tmp/vlc_output_completed.txt

echo "=== Export Complete ==="
echo "Results available at:"
echo "  - /tmp/vlc_output_config.txt (full config)"
echo "  - /tmp/vlc_output_summary.txt (summary)"
echo "  - /tmp/vlc_output_completed.txt (completion marker)"