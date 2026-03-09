#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Notification Sound Result ==="

NOTIFICATIONS_DIR="/home/ga/Music/notifications"
OUTPUT_FILE="${NOTIFICATIONS_DIR}/custom_notification.mp3"
EXPORT_BASE="/tmp/vlc_notification"

# Check if output file exists
if [ -f "${OUTPUT_FILE}" ]; then
    echo "✅ Notification sound found: ${OUTPUT_FILE}"
    
    # Copy to /tmp for verification
    cp "${OUTPUT_FILE}" "${EXPORT_BASE}_output.mp3"
    
    # Get file size
    FILE_SIZE=$(stat -f "%z" "${OUTPUT_FILE}" 2>/dev/null || stat -c "%s" "${OUTPUT_FILE}" 2>/dev/null || echo "0")
    FILE_SIZE_KB=$(echo "scale=2; ${FILE_SIZE} / 1024" | bc)
    
    echo "  File size: ${FILE_SIZE_KB} KB"
    
    # Get audio info using ffprobe
    if command -v ffprobe &> /dev/null; then
        echo "Analyzing audio with ffprobe..."
        
        ffprobe -v error -show_format -show_streams -of json \
            "${OUTPUT_FILE}" > "${EXPORT_BASE}_info.json" 2>&1 || true
        
        # Extract key properties for quick check
        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${OUTPUT_FILE}" 2>/dev/null || echo "0")
        CODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${OUTPUT_FILE}" 2>/dev/null || echo "unknown")
        SAMPLE_RATE=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "${OUTPUT_FILE}" 2>/dev/null || echo "0")
        CHANNELS=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "${OUTPUT_FILE}" 2>/dev/null || echo "0")
        BITRATE=$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "${OUTPUT_FILE}" 2>/dev/null || echo "0")
        
        echo "  Duration: ${DURATION} seconds"
        echo "  Codec: ${CODEC}"
        echo "  Sample rate: ${SAMPLE_RATE} Hz"
        echo "  Channels: ${CHANNELS}"
        echo "  Bitrate: ${BITRATE} bps"
    fi
    
    # List file details
    ls -lh "${OUTPUT_FILE}"
    
else
    echo "⚠️ Notification sound not found at expected location: ${OUTPUT_FILE}"
    echo "MISSING" > "${EXPORT_BASE}_status.txt"
    
    # Check if any MP3 files were created in notifications directory
    RECENT_MP3=$(find "${NOTIFICATIONS_DIR}" -name "*.mp3" -type f -mmin -10 2>/dev/null | head -1)
    
    if [ -n "${RECENT_MP3}" ]; then
        echo "Found recent MP3 file: ${RECENT_MP3}"
        cp "${RECENT_MP3}" "${EXPORT_BASE}_output.mp3"
        echo "FOUND_ALTERNATIVE" > "${EXPORT_BASE}_status.txt"
    fi
fi

# Export task parameters for verification
if [ -f "${NOTIFICATIONS_DIR}/task_params.json" ]; then
    cp "${NOTIFICATIONS_DIR}/task_params.json" "${EXPORT_BASE}_params.json"
fi

# List all files in notifications directory
ls -lh "${NOTIFICATIONS_DIR}" > "${EXPORT_BASE}_dir_listing.txt" 2>&1 || true

# Close VLC if running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force killing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > "${EXPORT_BASE}_completed.txt"
echo "Notification sound creation task completed" >> "${EXPORT_BASE}_completed.txt"

echo "=== Export Complete ==="
echo "Exported files:"
echo "  - ${EXPORT_BASE}_output.mp3 (notification sound)"
echo "  - ${EXPORT_BASE}_info.json (audio metadata)"
echo "  - ${EXPORT_BASE}_params.json (task parameters)"
echo "  - ${EXPORT_BASE}_completed.txt (completion marker)"