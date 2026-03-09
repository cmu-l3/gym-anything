#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Elderly-Friendly Viewing Result ==="

# Give VLC a moment to ensure any pending settings are written
sleep 1

# Check current VLC config before closing
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "VLC config file exists, checking for elderly-friendly settings..."
    
    # Quick scan for expected settings
    SETTINGS_FOUND=0
    
    grep -q "freetype-fontsize\|freetype-rel-fontsize" "$VLC_RC" && SETTINGS_FOUND=$((SETTINGS_FOUND + 1))
    grep -q "freetype-bold" "$VLC_RC" && SETTINGS_FOUND=$((SETTINGS_FOUND + 1))
    grep -q "norm-max-level\|audio-replay-gain" "$VLC_RC" && SETTINGS_FOUND=$((SETTINGS_FOUND + 1))
    grep -q "compressor\|norm-max-level" "$VLC_RC" && SETTINGS_FOUND=$((SETTINGS_FOUND + 1))
    grep -q "qt-minimal-view\|qt-privacy-ask" "$VLC_RC" && SETTINGS_FOUND=$((SETTINGS_FOUND + 1))
    
    echo "Initial scan found $SETTINGS_FOUND/5 setting categories configured"
else
    echo "⚠️ VLC config not found yet (may not have been saved)"
fi

# Close VLC gracefully to ensure settings are saved
if is_vlc_running; then
    echo "Closing VLC to save settings..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Close via keyboard
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    
    # Wait for VLC to close and save settings
    for i in {1..10}; do
        if ! is_vlc_running; then
            echo "VLC closed successfully"
            break
        fi
        sleep 1
    done
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
    fi
    
    # Wait for config to be written to disk
    sleep 2
fi

# Copy VLC config to temp location for verification
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlc_elderly_config.txt
    echo "✅ VLC config copied to /tmp/vlc_elderly_config.txt"
    
    # Print summary of found settings
    echo ""
    echo "Configuration Summary:"
    echo "----------------------"
    grep "freetype-fontsize\|freetype-rel-fontsize" /tmp/vlc_elderly_config.txt | head -2 || echo "  Subtitle size: not set"
    grep "freetype-bold" /tmp/vlc_elderly_config.txt | head -1 || echo "  Bold subtitles: not set"
    grep "norm-max-level\|audio-replay-gain-mode" /tmp/vlc_elderly_config.txt | head -2 || echo "  Audio normalization: not set"
    grep "audio-compressor\|compressor-ratio" /tmp/vlc_elderly_config.txt | head -2 || echo "  Audio compression: not set"
    grep "qt-minimal-view\|qt-privacy-ask" /tmp/vlc_elderly_config.txt | head -2 || echo "  Interface simplified: not set"
    grep "qt-updates-notif" /tmp/vlc_elderly_config.txt | head -1 || echo "  Update prompts: not set"
    echo "----------------------"
    
    # Also save a JSON summary for easier parsing
    cat > /tmp/vlc_elderly_result.json <<EOF
{
    "config_file_exists": true,
    "config_copied": true,
    "timestamp": "$(date -Iseconds)"
}
EOF
    
else
    echo "⚠️ VLC config file not found at $VLC_RC"
    
    cat > /tmp/vlc_elderly_result.json <<EOF
{
    "config_file_exists": false,
    "config_copied": false,
    "timestamp": "$(date -Iseconds)"
}
EOF
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_elderly_completed.txt
echo "Configure elderly-friendly viewing task completed" >> /tmp/vlc_elderly_completed.txt

echo "=== Export Complete ==="