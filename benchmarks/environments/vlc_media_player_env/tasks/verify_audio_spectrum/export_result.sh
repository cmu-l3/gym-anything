#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Audio Spectrum Result ==="

# Initialize result variables
VISUALIZER_ENABLED="false"
VISUALIZER_TYPE="none"
FILE_PLAYED="false"

# Check if VLC is running and try to query state
if is_vlc_running; then
    echo "VLC is running, gathering state..."
    
    # Take a screenshot to capture visual state
    DISPLAY=:1 import -window root /tmp/vlc_spectrum_screenshot.png 2>/dev/null || true
    
    # Wait a moment before closing to ensure config is written
    sleep 1
fi

# Close VLC gracefully to ensure config is saved
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC to save configuration..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Force kill if still running
if is_vlc_running; then
    echo "Force closing VLC..."
    kill_vlc ga
    sleep 1
fi

# Read VLC configuration file
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Reading VLC configuration..."
    
    # Check for audio-visual setting
    if grep -q "^audio-visual=" "$VLC_RC"; then
        VISUALIZER_TYPE=$(grep "^audio-visual=" "$VLC_RC" | cut -d= -f2 | head -1)
        if [ -n "$VISUALIZER_TYPE" ] && [ "$VISUALIZER_TYPE" != "none" ] && [ "$VISUALIZER_TYPE" != '""' ]; then
            VISUALIZER_ENABLED="true"
            echo "✅ Visualizer enabled: $VISUALIZER_TYPE"
        fi
    fi
    
    # Also check effect-list which might contain visual effects
    if grep -q "^effect-list=" "$VLC_RC"; then
        EFFECT_LIST=$(grep "^effect-list=" "$VLC_RC" | cut -d= -f2 | head -1)
        if echo "$EFFECT_LIST" | grep -qi "spectrum\|visual"; then
            VISUALIZER_ENABLED="true"
            echo "✅ Visual effects found in effect-list"
        fi
    fi
    
    # Copy config for verification
    cp "$VLC_RC" /tmp/vlc_spectrum_vlcrc.txt
else
    echo "⚠️ VLC config file not found"
fi

# Check for the specific audio file in recent files
if [ -f "$VLC_RC" ]; then
    if grep -q "questionable_hifi" "$VLC_RC"; then
        FILE_PLAYED="true"
        echo "✅ Target audio file found in VLC history"
    fi
fi

# Check media library
ML_PATHS=(
    "/home/ga/.local/share/vlc/ml.xspf"
    "/home/ga/.config/vlc/ml.xspf"
)

for ML_PATH in "${ML_PATHS[@]}"; do
    if [ -f "$ML_PATH" ]; then
        if grep -q "questionable_hifi" "$ML_PATH"; then
            FILE_PLAYED="true"
            echo "✅ Target audio file found in media library"
        fi
        # Copy media library
        cp "$ML_PATH" /tmp/vlc_spectrum_ml.xspf 2>/dev/null || true
    fi
done

# Write JSON result file
cat > /tmp/vlc_spectrum_result.json <<EOF
{
    "visualizer_enabled": $VISUALIZER_ENABLED,
    "visualizer_type": "$VISUALIZER_TYPE",
    "file_played": $FILE_PLAYED,
    "config_found": $([ -f "$VLC_RC" ] && echo "true" || echo "false")
}
EOF

echo "✅ Result saved to /tmp/vlc_spectrum_result.json"
cat /tmp/vlc_spectrum_result.json

echo "$(date)" > /tmp/vlc_spectrum_completed.txt
echo "Audio spectrum verification task completed" >> /tmp/vlc_spectrum_completed.txt

echo "=== Export Complete ==="