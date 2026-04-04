#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Practice Music Transcription Result ==="

# Initialize result variables
RUNTIME_SPEED=""
RUNTIME_FILTER=""
RUNTIME_CAPTURED="false"

# Query VLC RC interface for current playback rate
if is_vlc_running; then
    echo "Querying VLC RC interface for playback settings..."

    # Query playback rate from RC interface
    # VLC RC command 'get_rate' returns current playback rate as float
    RC_RATE_OUTPUT=$(echo "get_rate" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_RATE_OUTPUT" ]; then
        # Extract rate number (format can be "> 0.60" or just "0.60")
        RUNTIME_SPEED=$(echo "$RC_RATE_OUTPUT" | grep -oP '[\d.]+' | head -1)

        if [ -n "$RUNTIME_SPEED" ]; then
            RUNTIME_CAPTURED="true"
            echo "✅ Captured playback rate from VLC RC: $RUNTIME_SPEED"
        else
            echo "⚠️ Could not parse rate from RC output: $RC_RATE_OUTPUT"
        fi
    else
        echo "⚠️ Could not query RC interface for rate"
    fi

    # Query status for audio filter info
    STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$STATUS_OUTPUT" ]; then
        # Check for scaletempo or time-stretch mentions in status
        if echo "$STATUS_OUTPUT" | grep -iq "scaletempo\|time-stretch\|time stretch"; then
            RUNTIME_FILTER="scaletempo"
            echo "✅ Time-stretching filter detected in status"
        fi
    fi
fi

# Close VLC gracefully
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Force kill if still running
if is_vlc_running; then
    echo "Force closing VLC..."
    kill_vlc ga
    sleep 1
fi

# Read VLC configuration file (primary verification source)
VLC_RC="/home/ga/.config/vlc/vlcrc"
VLCRC_SPEED=""
VLCRC_FILTER=""
VLCRC_TIME_STRETCH=""

if [ -f "$VLC_RC" ]; then
    echo "Reading VLC configuration file..."
    
    # Check for rate/speed setting
    if grep -q "^rate=" "$VLC_RC"; then
        VLCRC_SPEED=$(grep "^rate=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Config speed: $VLCRC_SPEED"
    fi
    
    # Check for audio-time-stretch setting
    if grep -q "^audio-time-stretch=" "$VLC_RC"; then
        VLCRC_TIME_STRETCH=$(grep "^audio-time-stretch=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Time-stretch setting: $VLCRC_TIME_STRETCH"
    fi
    
    # Check for audio filter containing scaletempo
    if grep -q "^audio-filter=" "$VLC_RC"; then
        FILTER_LINE=$(grep "^audio-filter=" "$VLC_RC" | cut -d= -f2 | head -1)
        if echo "$FILTER_LINE" | grep -iq "scaletempo"; then
            VLCRC_FILTER="scaletempo"
            echo "Audio filter contains: $FILTER_LINE"
        fi
    fi
    
    # Alternative: check for scaletempo in any line
    if [ -z "$VLCRC_FILTER" ] && grep -iq "scaletempo" "$VLC_RC"; then
        VLCRC_FILTER="scaletempo"
        echo "Found scaletempo reference in config"
    fi
    
    # Copy entire config file for verification
    cp "$VLC_RC" /tmp/vlc_transcription_vlcrc.txt
else
    echo "⚠️ VLC config file not found: $VLC_RC"
fi

# Determine final values (prefer runtime, fallback to config)
FINAL_SPEED="${RUNTIME_SPEED:-${VLCRC_SPEED:-1.000000}}"
FINAL_FILTER="${RUNTIME_FILTER:-${VLCRC_FILTER}}"
FINAL_TIME_STRETCH="${VLCRC_TIME_STRETCH:-0}"

# Convert speed to percentage for readability
SPEED_PERCENT=$(echo "scale=1; $FINAL_SPEED * 100" | bc 2>/dev/null || echo "100")

# Write JSON result file
cat > /tmp/vlc_transcription_result.json <<EOF
{
    "speed": $FINAL_SPEED,
    "speed_percent": $SPEED_PERCENT,
    "time_stretch_enabled": $([ "$FINAL_TIME_STRETCH" = "1" ] && echo "true" || echo "false"),
    "audio_filter": "$FINAL_FILTER",
    "runtime_captured": $RUNTIME_CAPTURED,
    "config_found": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "source": "$([ "$RUNTIME_CAPTURED" = "true" ] && echo "rc" || echo "vlcrc")"
}
EOF

echo "✅ Transcription result saved to /tmp/vlc_transcription_result.json"
cat /tmp/vlc_transcription_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_transcription_completed.txt
echo "Practice music transcription task completed" >> /tmp/vlc_transcription_completed.txt
echo "Speed: $FINAL_SPEED, Filter: $FINAL_FILTER" >> /tmp/vlc_transcription_completed.txt

echo "=== Export Complete ==="