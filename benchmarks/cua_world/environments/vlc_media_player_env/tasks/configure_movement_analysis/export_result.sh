#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Movement Analysis Configuration Result ==="

# Initialize result variables
PLAYBACK_RATE="1.0"
RATE_CAPTURED="false"
AB_LOOP_ACTIVE="false"
AB_LOOP_DETECTED="false"
OSD_ENABLED="false"
RUNTIME_CAPTURED="false"

# Query VLC RC interface for current state
if is_vlc_running; then
    echo "Querying VLC RC interface for playback state..."

    # Query playback rate
    echo "Checking playback rate..."
    RATE_OUTPUT=$(echo "get_time" | nc -w 2 localhost:9999 2>/dev/null || echo "")
    
    # Try to get playback rate - VLC RC doesn't have direct rate command, 
    # so we'll check status which may include rate info
    STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost:9999 2>/dev/null || echo "")
    
    if [ -n "$STATUS_OUTPUT" ]; then
        # Try to extract rate from status (format varies)
        RATE_FROM_STATUS=$(echo "$STATUS_OUTPUT" | grep -oP '(?:rate|speed):\s*\K[\d.]+' | head -1)
        
        if [ -n "$RATE_FROM_STATUS" ]; then
            PLAYBACK_RATE="$RATE_FROM_STATUS"
            RATE_CAPTURED="true"
            echo "✅ Captured playback rate from RC: $PLAYBACK_RATE"
        fi
    fi
    
    # Check for A-B loop status
    # VLC RC may show loop status in info or status commands
    echo "Checking A-B loop status..."
    INFO_OUTPUT=$(echo "info" | nc -w 2 localhost:9999 2>/dev/null || echo "")
    
    if echo "$STATUS_OUTPUT $INFO_OUTPUT" | grep -qi "loop\|repeat\|ab"; then
        AB_LOOP_DETECTED="true"
        echo "✅ A-B loop indicators detected"
    fi
    
    # Additional check: if video is playing the same segment repeatedly
    # we can infer loop is active (check time twice with delay)
    TIME1=$(echo "get_time" | nc -w 1 localhost:9999 2>/dev/null | grep -oP '\d+' | head -1 || echo "0")
    sleep 3
    TIME2=$(echo "get_time" | nc -w 1 localhost:9999 2>/dev/null | grep -oP '\d+' | head -1 || echo "0")
    
    if [ -n "$TIME1" ] && [ -n "$TIME2" ]; then
        # If time went backwards or stayed in small range, loop might be active
        if [ "$TIME2" -lt "$TIME1" ] || ([ "$TIME2" -gt 0 ] && [ "$TIME2" -lt 10 ] && [ "$TIME1" -gt 0 ]); then
            AB_LOOP_ACTIVE="true"
            AB_LOOP_DETECTED="true"
            echo "✅ A-B loop appears active (time looping detected)"
        fi
    fi
    
    RUNTIME_CAPTURED="true"
else
    echo "⚠️ VLC not running, cannot query runtime state"
fi

# Close VLC to ensure settings are saved
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC to save settings..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga
        sleep 1
    fi
fi

# Read VLC configuration for OSD settings (persistent)
VLC_RC="/home/ga/.config/vlc/vlcrc"
VLC_QT_CONFIG="/home/ga/.config/vlc/vlc-qt-interface.conf"

echo "Reading VLC configuration files..."

# Check for OSD/time display settings in vlcrc
if [ -f "$VLC_RC" ]; then
    # Check various OSD-related settings
    if grep -qE '^(qt-time-display=1|qt-show-time=1|osd=1|video-title-show=0)' "$VLC_RC" 2>/dev/null; then
        OSD_ENABLED="true"
        echo "✅ OSD time display found in vlcrc"
    fi
    
    # Also check in Qt interface config
    if [ -f "$VLC_QT_CONFIG" ]; then
        if grep -qi "time.*display\|show.*time" "$VLC_QT_CONFIG" 2>/dev/null; then
            OSD_ENABLED="true"
            echo "✅ OSD settings found in Qt config"
        fi
    fi
    
    # If rate wasn't captured at runtime, try to find in config
    if [ "$RATE_CAPTURED" = "false" ]; then
        CONFIG_RATE=$(grep -oP '^rate=\K[\d.]+' "$VLC_RC" 2>/dev/null | head -1)
        if [ -n "$CONFIG_RATE" ]; then
            PLAYBACK_RATE="$CONFIG_RATE"
            echo "Fallback: found playback rate in config: $PLAYBACK_RATE"
        fi
    fi
else
    echo "⚠️ VLC config file not found"
fi

# Calculate playback percentage
PLAYBACK_PERCENT=$(echo "scale=0; $PLAYBACK_RATE * 100" | bc 2>/dev/null || echo "100")

# Write JSON result file
cat > /tmp/vlc_movement_analysis_result.json <<EOF
{
    "playback_rate": $PLAYBACK_RATE,
    "playback_percent": $PLAYBACK_PERCENT,
    "rate_captured": $RATE_CAPTURED,
    "ab_loop_detected": $AB_LOOP_DETECTED,
    "ab_loop_active": $AB_LOOP_ACTIVE,
    "osd_enabled": $OSD_ENABLED,
    "runtime_captured": $RUNTIME_CAPTURED,
    "config_checked": true
}
EOF

echo "✅ Movement analysis result saved to /tmp/vlc_movement_analysis_result.json"
cat /tmp/vlc_movement_analysis_result.json

# Copy config files for verification
echo "Copying config files for verification..."
cp "$VLC_RC" /tmp/vlc_movement_vlcrc.conf 2>/dev/null || echo "Could not copy vlcrc"
[ -f "$VLC_QT_CONFIG" ] && cp "$VLC_QT_CONFIG" /tmp/vlc_movement_qt.conf 2>/dev/null || true

# Create completion marker
echo "$(date)" > /tmp/vlc_movement_analysis_completed.txt
echo "Movement analysis configuration task completed" >> /tmp/vlc_movement_analysis_completed.txt
echo "Rate: $PLAYBACK_RATE, OSD: $OSD_ENABLED, Loop: $AB_LOOP_DETECTED" >> /tmp/vlc_movement_analysis_completed.txt

echo "=== Export Complete ==="