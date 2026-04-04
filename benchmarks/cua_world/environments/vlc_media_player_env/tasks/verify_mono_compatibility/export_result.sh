#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Mono Compatibility Result ==="

# Query VLC RC interface for current audio filter settings
AUDIO_FILTER=""
MONO_DETECTED="false"
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for audio settings..."

    # Query status from RC interface
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        echo "RC interface response received"
        
        # Check for mono-related keywords in status
        if echo "$RC_OUTPUT" | grep -iq "mono"; then
            MONO_DETECTED="true"
            RUNTIME_CAPTURED="true"
            echo "✅ Mono filter detected in runtime status"
        fi
    else
        echo "⚠️ Could not query RC interface"
    fi
fi

# Close VLC gracefully to ensure config is written
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC to persist configuration..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "VLC still running, force closing..."
        kill_vlc ga
        sleep 1
    fi
fi

# Read VLC config file for mono settings
VLC_RC="/home/ga/.config/vlc/vlcrc"
MONO_SETTINGS_FOUND="false"
MONO_METHOD=""

if [ -f "$VLC_RC" ]; then
    echo "Reading VLC configuration..."
    
    # Check for various mono configuration methods
    if grep -q "^audio-filter=.*mono" "$VLC_RC"; then
        AUDIO_FILTER=$(grep "^audio-filter=" "$VLC_RC" | cut -d= -f2 | head -1)
        MONO_SETTINGS_FOUND="true"
        MONO_METHOD="audio-filter"
        echo "✅ Found mono in audio-filter: $AUDIO_FILTER"
    fi
    
    if grep -q "^mono=1" "$VLC_RC"; then
        MONO_SETTINGS_FOUND="true"
        MONO_METHOD="${MONO_METHOD:+$MONO_METHOD,}mono=1"
        echo "✅ Found mono=1 setting"
    fi
    
    if grep -q "^stereo-to-mono=1" "$VLC_RC"; then
        MONO_SETTINGS_FOUND="true"
        MONO_METHOD="${MONO_METHOD:+$MONO_METHOD,}stereo-to-mono"
        echo "✅ Found stereo-to-mono=1 setting"
    fi
    
    if grep -q "^channels=1" "$VLC_RC"; then
        MONO_SETTINGS_FOUND="true"
        MONO_METHOD="${MONO_METHOD:+$MONO_METHOD,}channels=1"
        echo "✅ Found channels=1 setting"
    fi
    
    if grep -q "^audio-channel-mixer=.*mono" "$VLC_RC" || grep -q "^aout-channel-mixer=.*mono" "$VLC_RC"; then
        MONO_SETTINGS_FOUND="true"
        MONO_METHOD="${MONO_METHOD:+$MONO_METHOD,}channel-mixer"
        echo "✅ Found mono in channel mixer"
    fi
    
    # Copy vlcrc for verification
    cp "$VLC_RC" /tmp/vlc_mono_vlcrc
    echo "✅ VLC config copied for verification"
else
    echo "⚠️ VLC config file not found: $VLC_RC"
fi

# Create JSON result file with findings
cat > /tmp/vlc_mono_result.json <<EOF
{
    "mono_detected": $MONO_SETTINGS_FOUND,
    "mono_method": "$MONO_METHOD",
    "audio_filter": "$AUDIO_FILTER",
    "runtime_captured": $RUNTIME_CAPTURED,
    "config_file_exists": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✅ Mono compatibility result saved to /tmp/vlc_mono_result.json"
cat /tmp/vlc_mono_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_mono_completed.txt
echo "Mono compatibility verification task completed" >> /tmp/vlc_mono_completed.txt
echo "Mono settings found: $MONO_SETTINGS_FOUND" >> /tmp/vlc_mono_completed.txt
echo "Method used: $MONO_METHOD" >> /tmp/vlc_mono_completed.txt

echo "=== Export Complete ==="