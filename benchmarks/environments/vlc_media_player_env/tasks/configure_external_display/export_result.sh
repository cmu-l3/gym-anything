#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure External Display Result ==="

VLC_RC="/home/ga/.config/vlc/vlcrc"
DISPLAY_SETTINGS_FOUND="false"
DISPLAY_CONFIG="{}"

# Check VLC config file for display settings
if [ -f "$VLC_RC" ]; then
    echo "Reading VLC configuration file..."
    
    # Check for various display-related settings
    DISPLAY_KEYS=(
        "qt-fullscreen-screennumber"
        "qt-fullscreen-screenname"
        "fullscreen-screen"
        "vout-display"
        "x11-display"
    )
    
    CONFIG_JSON=""
    
    for key in "${DISPLAY_KEYS[@]}"; do
        if grep -q "^${key}=" "$VLC_RC"; then
            value=$(grep "^${key}=" "$VLC_RC" | cut -d= -f2- | head -1)
            echo "Found setting: ${key}=${value}"
            
            # Build JSON
            if [ -n "$CONFIG_JSON" ]; then
                CONFIG_JSON="${CONFIG_JSON},"
            fi
            CONFIG_JSON="${CONFIG_JSON}\"${key}\": \"${value}\""
            DISPLAY_SETTINGS_FOUND="true"
        fi
    done
    
    if [ -n "$CONFIG_JSON" ]; then
        DISPLAY_CONFIG="{${CONFIG_JSON}}"
    fi
    
    # Copy full config for detailed analysis
    cp "$VLC_RC" /tmp/vlc_display_config.txt
    echo "✅ VLC config copied for verification"
else
    echo "⚠️ VLC config file not found: $VLC_RC"
fi

# Close VLC gracefully to ensure config is saved
if is_vlc_running; then
    echo "Closing VLC to save configuration..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Use Ctrl+Q to quit and save preferences
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
        sleep 1
    fi
fi

# Re-read config after VLC closed (preferences may save on exit)
if [ -f "$VLC_RC" ]; then
    echo "Re-checking configuration after VLC exit..."
    
    CONFIG_JSON=""
    DISPLAY_SETTINGS_FOUND="false"
    
    for key in "${DISPLAY_KEYS[@]}"; do
        if grep -q "^${key}=" "$VLC_RC"; then
            value=$(grep "^${key}=" "$VLC_RC" | cut -d= -f2- | head -1)
            echo "Found setting after exit: ${key}=${value}"
            
            if [ -n "$CONFIG_JSON" ]; then
                CONFIG_JSON="${CONFIG_JSON},"
            fi
            CONFIG_JSON="${CONFIG_JSON}\"${key}\": \"${value}\""
            DISPLAY_SETTINGS_FOUND="true"
        fi
    done
    
    if [ -n "$CONFIG_JSON" ]; then
        DISPLAY_CONFIG="{${CONFIG_JSON}}"
    fi
    
    # Update exported config
    cp "$VLC_RC" /tmp/vlc_display_config.txt
fi

# Write JSON result file
cat > /tmp/vlc_display_result.json <<EOF
{
    "display_settings_found": ${DISPLAY_SETTINGS_FOUND},
    "display_config": ${DISPLAY_CONFIG},
    "config_file_path": "${VLC_RC}",
    "config_file_exists": $([ -f "$VLC_RC" ] && echo "true" || echo "false")
}
EOF

echo "✅ Display configuration result saved to /tmp/vlc_display_result.json"
cat /tmp/vlc_display_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_display_completed.txt
echo "Display configuration task completed" >> /tmp/vlc_display_completed.txt
echo "Settings found: ${DISPLAY_SETTINGS_FOUND}" >> /tmp/vlc_display_completed.txt

echo "=== Export Complete ==="