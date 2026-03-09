#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Switch Audio Output Device Result ==="

TASK_DIR="/home/ga/vlc_audio_output_task"
RESULT_JSON="/tmp/vlc_audio_output_result.json"

# Initialize result variables
AUDIO_SINK=""
AUDIO_SINK_ID=""
VLC_RUNNING="false"
VLC_PID=""
VLC_UPTIME_SEC=0
CONFIG_DEVICE=""
SINK_CORRECT="false"
RUNTIME_CAPTURED="false"

# Check if VLC is running
if is_vlc_running; then
    VLC_RUNNING="true"
    VLC_PID=$(pgrep -f "vlc" | head -1)
    echo "✅ VLC is running (PID: $VLC_PID)"
    
    # Get VLC uptime
    VLC_UPTIME_SEC=$(ps -p "$VLC_PID" -o etimes= 2>/dev/null | tr -d ' ' || echo "0")
    echo "VLC uptime: ${VLC_UPTIME_SEC}s"
    
    # Query VLC's current audio sink from PulseAudio
    echo "Querying PulseAudio for VLC's audio routing..."
    
    # Get all sink-inputs and find VLC's entry
    SINK_INPUTS=$(pactl list sink-inputs 2>/dev/null || echo "")
    
    if [ -n "$SINK_INPUTS" ]; then
        # Find VLC's sink input
        # Parse format: look for application.name = "vlc" then get the Sink: line
        VLC_SINK_INFO=$(echo "$SINK_INPUTS" | grep -A 30 "application.name = \"vlc\"" | grep "Sink:" | head -1 || echo "")
        
        if [ -n "$VLC_SINK_INFO" ]; then
            # Extract sink ID (number after #) or sink name
            AUDIO_SINK_ID=$(echo "$VLC_SINK_INFO" | grep -oP 'Sink:\s*\K\d+' || echo "")
            
            # Map sink ID to sink name
            if [ -n "$AUDIO_SINK_ID" ]; then
                AUDIO_SINK=$(pactl list short sinks | awk -v id="$AUDIO_SINK_ID" '$1 == id {print $2}')
                echo "✅ VLC audio routed to sink: $AUDIO_SINK (ID: $AUDIO_SINK_ID)"
                
                # Check if it matches reference_headphones
                if echo "$AUDIO_SINK" | grep -qi "reference_headphones\|headphones"; then
                    SINK_CORRECT="true"
                    echo "✅ Audio correctly routed to Reference_Headphones!"
                else
                    echo "⚠️ Audio routed to: $AUDIO_SINK (expected reference_headphones)"
                fi
                
                RUNTIME_CAPTURED="true"
            fi
        else
            echo "⚠️ VLC audio stream not found in PulseAudio sink-inputs"
        fi
    else
        echo "⚠️ Could not query PulseAudio sink-inputs"
    fi
else
    echo "⚠️ VLC is not running"
fi

# Read VLC configuration to check persistence
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    echo "Reading VLC configuration..."
    
    # Check for PulseAudio audio device setting
    if grep -q "^audio-device=" "$VLC_RC"; then
        CONFIG_DEVICE=$(grep "^audio-device=" "$VLC_RC" | cut -d= -f2- | head -1)
        echo "VLC config audio-device: $CONFIG_DEVICE"
    fi
    
    # Alternative: check pulse-specific settings
    if grep -q "^pulse-sink=" "$VLC_RC"; then
        PULSE_SINK=$(grep "^pulse-sink=" "$VLC_RC" | cut -d= -f2- | head -1)
        echo "VLC config pulse-sink: $PULSE_SINK"
        CONFIG_DEVICE="$PULSE_SINK"
    fi
    
    # Check if config mentions headphones
    if echo "$CONFIG_DEVICE" | grep -qi "headphones\|reference"; then
        echo "✅ VLC config shows headphones device"
    elif [ -n "$CONFIG_DEVICE" ]; then
        echo "⚠️ VLC config shows: $CONFIG_DEVICE"
    else
        echo "⚠️ No explicit device in VLC config (may use default)"
    fi
else
    echo "⚠️ VLC config file not found"
fi

# Get list of available sinks
AVAILABLE_SINKS=$(pactl list short sinks 2>/dev/null | awk '{print $2}' | tr '\n' ',' || echo "")

# Close VLC gracefully
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
        sleep 0.3
    fi
    
    echo "Closing VLC..."
    # Try RC interface quit first
    echo "quit" | nc -w 1 localhost 9999 2>/dev/null || true
    sleep 1
    
    # Fallback to keyboard shortcut
    if is_vlc_running; then
        safe_xdotool ga :1 key --delay 200 ctrl+q || true
        sleep 2
    fi
    
    # Final fallback: kill
    if is_vlc_running; then
        echo "⚠️ Forcing VLC to close..."
        kill_vlc ga
    fi
fi

# Write JSON result file
cat > "$RESULT_JSON" <<EOF
{
    "vlc_running": $VLC_RUNNING,
    "vlc_pid": "$VLC_PID",
    "vlc_uptime_seconds": $VLC_UPTIME_SEC,
    "audio_sink": "$AUDIO_SINK",
    "audio_sink_id": "$AUDIO_SINK_ID",
    "sink_correct": $SINK_CORRECT,
    "config_device": "$CONFIG_DEVICE",
    "runtime_captured": $RUNTIME_CAPTURED,
    "available_sinks": "$AVAILABLE_SINKS",
    "source": "$([ "$RUNTIME_CAPTURED" = "true" ] && echo "pulseaudio_runtime" || echo "vlcrc_config")"
}
EOF

echo ""
echo "✅ Audio output device result saved to $RESULT_JSON"
cat "$RESULT_JSON"

# Export PulseAudio state for debugging
pactl list short sinks > /tmp/vlc_pulseaudio_sinks.txt 2>/dev/null || true
pactl list sink-inputs > /tmp/vlc_pulseaudio_sink_inputs.txt 2>/dev/null || true

# Copy VLC config
cp "$VLC_RC" /tmp/vlc_audio_output_vlcrc 2>/dev/null || echo "# VLC config not found" > /tmp/vlc_audio_output_vlcrc

# Create completion marker
echo "$(date)" > /tmp/vlc_audio_output_completed.txt
echo "Task completed - VLC uptime: ${VLC_UPTIME_SEC}s" >> /tmp/vlc_audio_output_completed.txt

echo ""
echo "=== Export Complete ==="