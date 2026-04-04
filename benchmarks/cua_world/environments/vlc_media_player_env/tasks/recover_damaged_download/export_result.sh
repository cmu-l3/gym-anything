#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Recover Damaged Download Result ==="

# Check for recovered video at expected location
RECOVERED_FILE="/home/ga/Videos/recovered/lecture_recovered.mp4"
EXPORT_FILE="/tmp/vlc_recovered_video.mp4"
FOUND="false"

if [ -f "${RECOVERED_FILE}" ]; then
    echo "✅ Recovered file found at expected location: ${RECOVERED_FILE}"
    cp "${RECOVERED_FILE}" "${EXPORT_FILE}"
    FOUND="true"
    
    # Get basic file info
    FILE_SIZE=$(stat -c%s "${RECOVERED_FILE}" 2>/dev/null || stat -f%z "${RECOVERED_FILE}")
    FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE / 1048576" | bc)
    echo "   Size: ${FILE_SIZE_MB} MB"
    
    # Try to get duration using ffprobe
    if command -v ffprobe &> /dev/null; then
        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${RECOVERED_FILE}" 2>/dev/null || echo "unknown")
        if [ "$DURATION" != "unknown" ]; then
            DURATION_MIN=$(echo "scale=1; $DURATION / 60" | bc)
            echo "   Duration: ${DURATION_MIN} minutes"
        fi
    fi
else
    echo "⚠️  Recovered file not found at expected location: ${RECOVERED_FILE}"
    
    # Search for any recently created video files in recovered directory
    RECOVERED_DIR="/home/ga/Videos/recovered"
    if [ -d "${RECOVERED_DIR}" ]; then
        echo "Searching for recent files in ${RECOVERED_DIR}..."
        RECENT_FILE=$(find "${RECOVERED_DIR}" -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -15 2>/dev/null | head -1)
        
        if [ -n "${RECENT_FILE}" ]; then
            echo "Found recent video file: ${RECENT_FILE}"
            cp "${RECENT_FILE}" "${EXPORT_FILE}"
            FOUND="true"
        fi
    fi
fi

# Export detailed media info if file was found
if [ "${FOUND}" = "true" ] && [ -f "${EXPORT_FILE}" ]; then
    if command -v ffprobe &> /dev/null; then
        echo "Exporting detailed media information..."
        ffprobe -v error -show_format -show_streams -of json "${EXPORT_FILE}" > /tmp/vlc_recovered_info.json 2>&1 || echo '{"error": "ffprobe failed"}' > /tmp/vlc_recovered_info.json
    else
        echo '{"error": "ffprobe not available"}' > /tmp/vlc_recovered_info.json
    fi
    
    # Quick playback test (first 5 seconds)
    echo "Running quick playback test..."
    if command -v ffmpeg &> /dev/null; then
        timeout 10 ffmpeg -v error -i "${EXPORT_FILE}" -t 5 -f null - 2>&1 | head -n 50 > /tmp/vlc_playback_test.log || echo "Playback test failed or timeout" >> /tmp/vlc_playback_test.log
    fi
else
    echo '{"error": "no recovered file found"}' > /tmp/vlc_recovered_info.json
    echo "No file to test" > /tmp/vlc_playback_test.log
fi

# Copy recovery info for verifier reference
cp /tmp/vlc_recovery_info.txt /tmp/vlc_recovery_metadata.txt 2>/dev/null || echo "original_size=0" > /tmp/vlc_recovery_metadata.txt

# Close VLC if still running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Force kill if still running
if is_vlc_running; then
    echo "Force killing VLC..."
    kill_vlc ga
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_recovery_completed.txt
echo "Recovery task exported" >> /tmp/vlc_recovery_completed.txt
echo "Recovered file found: ${FOUND}" >> /tmp/vlc_recovery_completed.txt

echo "=== Export Complete ==="
[ "${FOUND}" = "true" ] && echo "✅ Recovered file ready for verification" || echo "❌ No recovered file found"