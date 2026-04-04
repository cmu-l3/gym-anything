#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Identify Bird Call Result ==="

# Check for output file in expected location
EXPECTED_OUTPUT="/home/ga/Recordings/unknown_warbler_call"
FOUND_FILE=""

# Check multiple possible extensions
for ext in mp3 wav ogg flac m4a; do
    if [ -f "${EXPECTED_OUTPUT}.${ext}" ]; then
        echo "✅ Found output: unknown_warbler_call.${ext}"
        FOUND_FILE="${EXPECTED_OUTPUT}.${ext}"
        cp "$FOUND_FILE" "/tmp/vlc_bird_call_output.${ext}"
        break
    fi
done

# If not found in expected location, check other common locations
if [ -z "$FOUND_FILE" ]; then
    echo "⚠️ Expected output not found, checking alternate locations..."
    
    # Check Videos directory (VLC default recording location)
    for ext in mp3 wav ogg flac m4a; do
        if [ -f "/home/ga/Videos/unknown_warbler_call.${ext}" ]; then
            echo "Found in Videos: unknown_warbler_call.${ext}"
            FOUND_FILE="/home/ga/Videos/unknown_warbler_call.${ext}"
            cp "$FOUND_FILE" "/tmp/vlc_bird_call_output.${ext}"
            break
        fi
    done
fi

# Check for VLC recordings with automatic naming (vlc-record-*)
if [ -z "$FOUND_FILE" ]; then
    echo "Checking for VLC auto-recorded files..."
    
    # Find most recent vlc-record file in Videos directory (created in last 10 minutes)
    RECENT_RECORDING=$(find /home/ga/Videos -name "vlc-record-*" -type f -mmin -10 2>/dev/null | sort -r | head -1)
    
    if [ -n "$RECENT_RECORDING" ] && [ -f "$RECENT_RECORDING" ]; then
        echo "Found recent VLC recording: $RECENT_RECORDING"
        FOUND_FILE="$RECENT_RECORDING"
        EXT="${RECENT_RECORDING##*.}"
        cp "$RECENT_RECORDING" "/tmp/vlc_bird_call_output.${EXT}"
    fi
fi

# Check Music directory as fallback
if [ -z "$FOUND_FILE" ]; then
    for ext in mp3 wav ogg flac; do
        if [ -f "/home/ga/Music/unknown_warbler_call.${ext}" ]; then
            echo "Found in Music: unknown_warbler_call.${ext}"
            FOUND_FILE="/home/ga/Music/unknown_warbler_call.${ext}"
            cp "$FOUND_FILE" "/tmp/vlc_bird_call_output.${ext}"
            break
        fi
    done
fi

# Check for any recent audio files in Recordings directory
if [ -z "$FOUND_FILE" ]; then
    echo "Checking for any recent audio files in Recordings..."
    RECENT_AUDIO=$(find /home/ga/Recordings -type f \( -name "*.mp3" -o -name "*.wav" -o -name "*.ogg" -o -name "*.flac" \) -mmin -10 2>/dev/null | grep -v "morning_birding" | head -1)
    
    if [ -n "$RECENT_AUDIO" ] && [ -f "$RECENT_AUDIO" ]; then
        echo "Found recent audio file: $RECENT_AUDIO"
        FOUND_FILE="$RECENT_AUDIO"
        EXT="${RECENT_AUDIO##*.}"
        cp "$RECENT_AUDIO" "/tmp/vlc_bird_call_output.${EXT}"
    fi
fi

if [ -n "$FOUND_FILE" ]; then
    echo "✅ Output file found: $FOUND_FILE"
    ls -lh "$FOUND_FILE"
    
    # Get file info if ffprobe available
    if command -v ffprobe &> /dev/null; then
        echo "File info:"
        ffprobe -v error -show_entries format=duration,size,bit_rate \
            -show_entries stream=codec_name,sample_rate,channels \
            "$FOUND_FILE" 2>&1 | head -20 || true
    fi
else
    echo "❌ No output file found!"
fi

# Close VLC if running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_bird_call_completed.txt
echo "Bird call extraction task completed" >> /tmp/vlc_bird_call_completed.txt
if [ -n "$FOUND_FILE" ]; then
    echo "Output file: $FOUND_FILE" >> /tmp/vlc_bird_call_completed.txt
fi

echo "=== Export Complete ==="