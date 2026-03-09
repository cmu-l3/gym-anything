#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Practice Loop Result ==="

EXPORT_JSON="/tmp/vlc_practice_loop_result.json"
LOG_FILE="/tmp/vlc_practice_loop_export.log"

# Initialize result variables
RUNTIME_SPEED=""
RUNTIME_AB_STATE=""
CONFIG_SPEED=""
CONFIG_TIMESTRETCH=""
CONFIG_AB_REPEAT=""
SPEED_CAPTURED="false"
AB_CAPTURED="false"

# Query VLC RC interface for current state
if is_vlc_running; then
    echo "Querying VLC RC interface..." | tee -a "$LOG_FILE"
    
    # Query playback rate
    RATE_OUTPUT=$(echo "get_rate" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -z "$RATE_OUTPUT" ]; then
        # Try alternative command
        RATE_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null | grep -i "rate" || echo "")
    fi
    
    if [ -n "$RATE_OUTPUT" ]; then
        # Extract rate value (format may vary: "1.00" or "( rate: 1.00 )")
        RUNTIME_SPEED=$(echo "$RATE_OUTPUT" | grep -oP '[\d.]+' | head -1)
        
        if [ -n "$RUNTIME_SPEED" ]; then
            SPEED_CAPTURED="true"
            echo "✅ Captured playback rate from RC: $RUNTIME_SPEED" | tee -a "$LOG_FILE"
        fi
    fi
    
    # Try to detect A-B repeat state (VLC RC may not expose this directly)
    # Check if video position loops back (primitive detection)
    POS1=$(echo "get_time" | nc -w 1 localhost 9999 2>/dev/null | grep -oP '\d+' || echo "0")
    sleep 2
    POS2=$(echo "get_time" | nc -w 1 localhost 9999 2>/dev/null | grep -oP '\d+' || echo "0")
    
    if [ -n "$POS1" ] && [ -n "$POS2" ]; then
        # If position decreased or stayed in same range, might be looping
        if [ "$POS2" -lt "$POS1" ] || ([ "$POS1" -ge 90 ] && [ "$POS1" -le 120 ] && [ "$POS2" -ge 90 ] && [ "$POS2" -le 120 ]); then
            RUNTIME_AB_STATE="active"
            AB_CAPTURED="true"
            echo "✅ A-B loop may be active (position: $POS1 → $POS2)" | tee -a "$LOG_FILE"
        fi
    fi
fi

# Close VLC gracefully
if is_vlc_running; then
    echo "Closing VLC..." | tee -a "$LOG_FILE"
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Try RC quit first
    echo "quit" | nc -w 1 localhost 9999 2>/dev/null || true
    sleep 1
    
    # Force close if still running
    if is_vlc_running; then
        safe_xdotool ga :1 key --delay 200 ctrl+q || true
        sleep 2
    fi
fi

# Read VLC configuration files
VLC_RC="/home/ga/.config/vlc/vlcrc"
VLC_QT_CONF="/home/ga/.config/vlc/vlc-qt-interface.conf"

echo "Reading VLC configuration files..." | tee -a "$LOG_FILE"

# Parse vlcrc
if [ -f "$VLC_RC" ]; then
    echo "Parsing vlcrc..." | tee -a "$LOG_FILE"
    
    # Get rate setting
    if grep -q "^rate=" "$VLC_RC"; then
        CONFIG_SPEED=$(grep "^rate=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Config rate: $CONFIG_SPEED" | tee -a "$LOG_FILE"
    fi
    
    # Get time-stretch setting
    if grep -q "^audio-time-stretch=" "$VLC_RC"; then
        CONFIG_TIMESTRETCH=$(grep "^audio-time-stretch=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Config time-stretch: $CONFIG_TIMESTRETCH" | tee -a "$LOG_FILE"
    elif grep -q "^time-stretching-audio=" "$VLC_RC"; then
        CONFIG_TIMESTRETCH=$(grep "^time-stretching-audio=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Config time-stretching-audio: $CONFIG_TIMESTRETCH" | tee -a "$LOG_FILE"
    fi
    
    # Check for A-B repeat settings
    if grep -q "^input-repeat=" "$VLC_RC"; then
        REPEAT_VAL=$(grep "^input-repeat=" "$VLC_RC" | cut -d= -f2 | head -1)
        if [ "$REPEAT_VAL" != "0" ]; then
            CONFIG_AB_REPEAT="enabled"
            echo "Config input-repeat: $REPEAT_VAL" | tee -a "$LOG_FILE"
        fi
    fi
    
    # Check for explicit A-B loop points
    if grep -q "^ab-loop-a=" "$VLC_RC"; then
        LOOP_A=$(grep "^ab-loop-a=" "$VLC_RC" | cut -d= -f2 | head -1)
        LOOP_B=$(grep "^ab-loop-b=" "$VLC_RC" | cut -d= -f2 | head -1 || echo "0")
        
        if [ -n "$LOOP_A" ] && [ "$LOOP_A" != "0" ]; then
            CONFIG_AB_REPEAT="points_set"
            AB_CAPTURED="true"
            echo "Config A-B points: A=$LOOP_A, B=$LOOP_B" | tee -a "$LOG_FILE"
        fi
    fi
    
    # Copy vlcrc for verification
    cp "$VLC_RC" /tmp/vlcrc 2>/dev/null || true
else
    echo "⚠️ vlcrc not found" | tee -a "$LOG_FILE"
fi

# Parse Qt interface config
if [ -f "$VLC_QT_CONF" ]; then
    echo "Parsing Qt config..." | tee -a "$LOG_FILE"
    
    # Look for A-B loop settings in Qt config
    if grep -qi "abloop" "$VLC_QT_CONF" || grep -qi "ab-loop" "$VLC_QT_CONF"; then
        CONFIG_AB_REPEAT="qt_config"
        AB_CAPTURED="true"
        echo "Found A-B loop settings in Qt config" | tee -a "$LOG_FILE"
    fi
    
    # Copy Qt config for verification
    cp "$VLC_QT_CONF" /tmp/vlc-qt-interface.conf 2>/dev/null || true
else
    echo "Qt config not found" | tee -a "$LOG_FILE"
fi

# Determine final values (runtime takes precedence over config)
FINAL_SPEED="${RUNTIME_SPEED:-${CONFIG_SPEED:-1.0}}"
FINAL_TIMESTRETCH="${CONFIG_TIMESTRETCH:-0}"
FINAL_AB_REPEAT="${RUNTIME_AB_STATE:-${CONFIG_AB_REPEAT:-none}}"

# Write JSON result
cat > "$EXPORT_JSON" <<EOF
{
    "playback_speed": "$FINAL_SPEED",
    "time_stretch_enabled": "$FINAL_TIMESTRETCH",
    "ab_repeat_state": "$FINAL_AB_REPEAT",
    "runtime_speed_captured": $SPEED_CAPTURED,
    "ab_loop_detected": $AB_CAPTURED,
    "config_files_found": $([ -f "/tmp/vlcrc" ] && echo "true" || echo "false")
}
EOF

echo "✅ Practice loop result saved to $EXPORT_JSON" | tee -a "$LOG_FILE"
cat "$EXPORT_JSON" | tee -a "$LOG_FILE"

# Create completion marker
echo "$(date)" > /tmp/vlc_practice_loop_completed.txt
echo "Practice loop task export completed" >> /tmp/vlc_practice_loop_completed.txt

echo "=== Export Complete ===" | tee -a "$LOG_FILE"