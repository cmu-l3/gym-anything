#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Adjust Playback Speed Result ==="

# Query VLC RC interface for current playback rate
RUNTIME_RATE=""
RATE_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for playback rate..."

    # Method 1: Try get_rate command
    RC_OUTPUT=$(echo "get_rate" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$RC_OUTPUT" ]; then
        # Extract rate value (format varies, could be "> 1.5" or just "1.5")
        RUNTIME_RATE=$(echo "$RC_OUTPUT" | grep -oP '>\s*\K\d+\.?\d*|\d+\.?\d+' | head -1)
        
        if [ -n "$RUNTIME_RATE" ]; then
            # Validate rate is in reasonable range (0.25 to 4.0)
            if awk "BEGIN {exit !($RUNTIME_RATE >= 0.25 && $RUNTIME_RATE <= 4.0)}"; then
                RATE_CAPTURED="true"
                echo "✅ Captured playback rate from VLC RC: ${RUNTIME_RATE}x"
            else
                echo "⚠️ Rate out of valid range: $RUNTIME_RATE"
                RUNTIME_RATE=""
            fi
        fi
    fi
    
    # Method 2: Try status command as fallback
    if [ "$RATE_CAPTURED" = "false" ]; then
        echo "Trying status command for rate..."
        STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
        
        if [ -n "$STATUS_OUTPUT" ]; then
            # Look for rate in status output (format: "rate: 1.5" or similar)
            RUNTIME_RATE=$(echo "$STATUS_OUTPUT" | grep -oP 'rate[:\s]+\K\d+\.?\d*' | head -1)
            
            if [ -n "$RUNTIME_RATE" ] && awk "BEGIN {exit !($RUNTIME_RATE >= 0.25 && $RUNTIME_RATE <= 4.0)}"; then
                RATE_CAPTURED="true"
                echo "✅ Captured rate from status: ${RUNTIME_RATE}x"
            fi
        fi
    fi
    
    if [ "$RATE_CAPTURED" = "false" ]; then
        echo "⚠️ Could not query playback rate via RC interface"
    fi
fi

# Close VLC gracefully to ensure config is saved
if is_vlc_running; then
    {
        wid=$(get_vlc_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid" || true
        fi
        echo "Closing VLC gracefully..."
        safe_xdotool ga :1 key --delay 200 ctrl+q
        sleep 2
    } || {
        echo "⚠️ Failed to close VLC gracefully; forcing..."
        kill_vlc ga
        sleep 1
    }
fi

# Fallback: Read playback rate from VLC config if RC query failed
VLC_RC="/home/ga/.config/vlc/vlcrc"
VLCRC_RATE=""

if [ "$RATE_CAPTURED" = "false" ] && [ -f "$VLC_RC" ]; then
    echo "Fallback: reading playback rate from vlcrc..."
    
    # VLC stores rate as floating point (e.g., rate=1.5 or playback-speed=1.5)
    if grep -q "^rate=" "$VLC_RC"; then
        VLCRC_RATE=$(grep "^rate=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Rate from vlcrc: ${VLCRC_RATE}x"
    elif grep -q "^playback-speed=" "$VLC_RC"; then
        VLCRC_RATE=$(grep "^playback-speed=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Playback speed from vlcrc: ${VLCRC_RATE}x"
    else
        echo "⚠️ No rate setting found in vlcrc (may be at default 1.0)"
        VLCRC_RATE="1.0"
    fi
fi

# Use runtime rate if captured, otherwise fallback to vlcrc
FINAL_RATE="${RUNTIME_RATE:-${VLCRC_RATE:-1.0}}"

# Calculate percentage (1.0 = 100%, 1.5 = 150%)
RATE_PERCENT=$(echo "scale=1; $FINAL_RATE * 100" | bc)

# Write JSON result file
cat > /tmp/vlc_speed_result.json <<EOF
{
    "rate": $FINAL_RATE,
    "rate_percent": $RATE_PERCENT,
    "runtime_captured": $RATE_CAPTURED,
    "source": "$([ "$RATE_CAPTURED" = "true" ] && echo "rc" || echo "vlcrc")"
}
EOF

echo "✅ Playback speed result saved to /tmp/vlc_speed_result.json"
cat /tmp/vlc_speed_result.json

# Write completion marker
echo "$(date)" > /tmp/vlc_speed_completed.txt
echo "Playback speed task completed" >> /tmp/vlc_speed_completed.txt
echo "Runtime rate captured: ${RATE_CAPTURED}" >> /tmp/vlc_speed_completed.txt
echo "Final rate: ${FINAL_RATE}x" >> /tmp/vlc_speed_completed.txt

echo "=== Export Complete ==="