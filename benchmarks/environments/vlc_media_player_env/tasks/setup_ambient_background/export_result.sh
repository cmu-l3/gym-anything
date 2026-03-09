#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Ambient Background Configuration Result ==="

# Query VLC RC interface for current runtime settings
RUNTIME_VOLUME=""
RUNTIME_LOOP=""
RUNTIME_REPEAT=""
VOLUME_CAPTURED="false"
LOOP_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for runtime settings..."
    
    # Query current volume
    RC_OUTPUT=$(echo "volume" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$RC_OUTPUT" ]; then
        RUNTIME_VOLUME=$(echo "$RC_OUTPUT" | grep -oP '(?:audio volume:|>)\s*\K\d+' | head -1)
        if [ -n "$RUNTIME_VOLUME" ]; then
            VOLUME_CAPTURED="true"
            echo "✅ Captured runtime volume: $RUNTIME_VOLUME"
        fi
    fi
    
    # Query loop/repeat status
    STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$STATUS_OUTPUT" ]; then
        # Check for loop indicators in status
        if echo "$STATUS_OUTPUT" | grep -qi "loop\|repeat"; then
            RUNTIME_LOOP="enabled"
            LOOP_CAPTURED="true"
            echo "✅ Loop appears to be enabled (from status)"
        fi
    fi
    
    # Try to query repeat setting directly
    REPEAT_OUTPUT=$(echo "get_repeat" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$REPEAT_OUTPUT" ]; then
        if echo "$REPEAT_OUTPUT" | grep -qi "true\|on\|1"; then
            RUNTIME_REPEAT="true"
            LOOP_CAPTURED="true"
            echo "✅ Repeat confirmed: $RUNTIME_REPEAT"
        fi
    fi
fi

# Force settings to be written to config by closing VLC properly
if is_vlc_running; then
    echo "Closing VLC to ensure settings are saved..."
    
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Use keyboard shortcut to close (saves settings)
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    
    # Wait for VLC to close and write config
    for i in {1..10}; do
        if ! is_vlc_running; then
            echo "VLC closed successfully"
            break
        fi
        echo "Waiting for VLC to close... ($i/10)"
        sleep 1
    done
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force killing VLC..."
        kill_vlc ga
    fi
    
    # Give filesystem time to sync
    sleep 2
fi

# Read VLC config file for persistent settings
VLC_RC="/home/ga/.config/vlc/vlcrc"
CONFIG_VOLUME=""
CONFIG_LOOP=""
CONFIG_REPEAT=""
CONFIG_INPUT_REPEAT=""
CONFIG_MINIMAL=""
CONFIG_PRIVACY=""

if [ -f "$VLC_RC" ]; then
    echo "Reading VLC config file..."
    
    # Extract relevant settings
    CONFIG_VOLUME=$(grep "^audio-volume=" "$VLC_RC" 2>/dev/null | cut -d= -f2 | head -1 || echo "")
    CONFIG_LOOP=$(grep "^loop=" "$VLC_RC" 2>/dev/null | cut -d= -f2 | head -1 || echo "")
    CONFIG_REPEAT=$(grep "^repeat=" "$VLC_RC" 2>/dev/null | cut -d= -f2 | head -1 || echo "")
    CONFIG_INPUT_REPEAT=$(grep "^input-repeat=" "$VLC_RC" 2>/dev/null | cut -d= -f2 | head -1 || echo "")
    CONFIG_MINIMAL=$(grep "^qt-minimal-view=" "$VLC_RC" 2>/dev/null | cut -d= -f2 | head -1 || echo "")
    CONFIG_PRIVACY=$(grep "^qt-privacy-ask=" "$VLC_RC" 2>/dev/null | cut -d= -f2 | head -1 || echo "")
    
    echo "Config volume: $CONFIG_VOLUME"
    echo "Config loop: $CONFIG_LOOP"
    echo "Config repeat: $CONFIG_REPEAT"
    echo "Config input-repeat: $CONFIG_INPUT_REPEAT"
    echo "Config minimal view: $CONFIG_MINIMAL"
else
    echo "⚠️ VLC config file not found: $VLC_RC"
fi

# Copy VLC config to temp location for verification
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlc_ambient_config.txt
    echo "✅ VLC config copied to /tmp/vlc_ambient_config.txt"
else
    echo "{}" > /tmp/vlc_ambient_config.txt
    echo "⚠️ Created empty config file"
fi

# Determine final volume (prefer config over runtime)
FINAL_VOLUME="${CONFIG_VOLUME:-${RUNTIME_VOLUME:-256}}"

# Determine final loop status
FINAL_LOOP="false"
if [ "$CONFIG_LOOP" = "1" ] || [ "$CONFIG_REPEAT" = "one" ] || [ -n "$CONFIG_INPUT_REPEAT" ]; then
    FINAL_LOOP="true"
elif [ "$RUNTIME_LOOP" = "enabled" ] || [ "$RUNTIME_REPEAT" = "true" ]; then
    FINAL_LOOP="true"
fi

# Determine minimal interface status
MINIMAL_INTERFACE="false"
if [ "$CONFIG_MINIMAL" = "1" ] || [ "$CONFIG_PRIVACY" = "0" ]; then
    MINIMAL_INTERFACE="true"
fi

# Calculate volume percentage
VOLUME_PERCENT=$(echo "scale=1; $FINAL_VOLUME / 256 * 100" | bc 2>/dev/null || echo "100")

# Write JSON result file
cat > /tmp/vlc_ambient_result.json <<EOF
{
    "volume": $FINAL_VOLUME,
    "volume_percent": $VOLUME_PERCENT,
    "loop_enabled": $FINAL_LOOP,
    "minimal_interface": $MINIMAL_INTERFACE,
    "config_volume": "$CONFIG_VOLUME",
    "config_loop": "$CONFIG_LOOP",
    "config_repeat": "$CONFIG_REPEAT",
    "config_input_repeat": "$CONFIG_INPUT_REPEAT",
    "config_minimal": "$CONFIG_MINIMAL",
    "runtime_volume": "$RUNTIME_VOLUME",
    "runtime_loop": "$RUNTIME_LOOP",
    "volume_captured": $VOLUME_CAPTURED,
    "loop_captured": $LOOP_CAPTURED
}
EOF

echo "✅ Ambient configuration result saved to /tmp/vlc_ambient_result.json"
cat /tmp/vlc_ambient_result.json

echo "$(date)" > /tmp/vlc_ambient_completed.txt
echo "Ambient background configuration task completed" >> /tmp/vlc_ambient_completed.txt
echo "Volume: $FINAL_VOLUME ($VOLUME_PERCENT%)" >> /tmp/vlc_ambient_completed.txt
echo "Loop: $FINAL_LOOP" >> /tmp/vlc_ambient_completed.txt
echo "Minimal interface: $MINIMAL_INTERFACE" >> /tmp/vlc_ambient_completed.txt

echo "=== Export Complete ==="