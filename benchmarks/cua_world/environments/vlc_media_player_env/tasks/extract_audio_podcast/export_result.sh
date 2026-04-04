#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Extract Audio Podcast Result ==="

# Create results directory
RESULTS_DIR="/tmp/task_results/extract_audio_podcast"
mkdir -p "$RESULTS_DIR"

# Check for converted audio file at expected location
EXPECTED_OUTPUT="/home/ga/Music/podcasts/Tech_Conference_2024.mp3"
FOUND_OUTPUT=""

if [ -f "$EXPECTED_OUTPUT" ]; then
    echo "✅ Converted audio found: $EXPECTED_OUTPUT"
    FOUND_OUTPUT="$EXPECTED_OUTPUT"
    cp "$EXPECTED_OUTPUT" "$RESULTS_DIR/output_audio.mp3"
    ls -lh "$EXPECTED_OUTPUT"
else
    echo "⚠️ Expected audio file not found at: $EXPECTED_OUTPUT"
    
    # Look for any recently created MP3 in podcasts directory (within last 10 minutes)
    RECENT_MP3=$(find /home/ga/Music/podcasts -name "*.mp3" -type f -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_MP3" ]; then
        echo "Found recent MP3: $RECENT_MP3"
        FOUND_OUTPUT="$RECENT_MP3"
        cp "$RECENT_MP3" "$RESULTS_DIR/output_audio.mp3"
        ls -lh "$RECENT_MP3"
    else
        echo "❌ No MP3 files found in output directory"
        
        # Check for any MP3 anywhere in Music directory as last resort
        ANY_MP3=$(find /home/ga/Music -name "*.mp3" -type f -mmin -10 2>/dev/null | head -1)
        if [ -n "$ANY_MP3" ]; then
            echo "Found MP3 in Music directory: $ANY_MP3"
            FOUND_OUTPUT="$ANY_MP3"
            cp "$ANY_MP3" "$RESULTS_DIR/output_audio.mp3"
        fi
    fi
fi

# Copy source video for verification comparison
if [ -f /home/ga/Videos/conferences/Tech_Conference_2024.mp4 ]; then
    cp /home/ga/Videos/conferences/Tech_Conference_2024.mp4 "$RESULTS_DIR/source_video.mp4" || true
    echo "✅ Source video copied for verification"
fi

# Copy VLC logs if available
cp /tmp/vlc_extract_audio_task.log "$RESULTS_DIR/vlc_task.log" 2>/dev/null || true
cp /home/ga/.config/vlc/vlc-qt-interface.conf "$RESULTS_DIR/vlc_config.conf" 2>/dev/null || true

# Close VLC
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
        echo "Force closing VLC..."
        kill_vlc ga
    fi
fi

# Create standardized output file for verifier
if [ -f "$RESULTS_DIR/output_audio.mp3" ]; then
    cp "$RESULTS_DIR/output_audio.mp3" /tmp/vlc_extracted_audio.mp3
    echo "✅ Audio copied to /tmp/vlc_extracted_audio.mp3"
fi

if [ -f "$RESULTS_DIR/source_video.mp4" ]; then
    cp "$RESULTS_DIR/source_video.mp4" /tmp/vlc_source_video.mp4
    echo "✅ Source video copied to /tmp/vlc_source_video.mp4"
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_extract_audio_completed.txt
echo "Audio extraction task completed" >> /tmp/vlc_extract_audio_completed.txt
if [ -n "$FOUND_OUTPUT" ]; then
    echo "Output file: $FOUND_OUTPUT" >> /tmp/vlc_extract_audio_completed.txt
fi

# Create manifest
cat > "$RESULTS_DIR/manifest.json" << EOF
{
  "task_id": "extract_audio_podcast@1",
  "timestamp": "$(date -Iseconds)",
  "source_video": "/home/ga/Videos/conferences/Tech_Conference_2024.mp4",
  "expected_output": "$EXPECTED_OUTPUT",
  "found_output": "$FOUND_OUTPUT",
  "output_exists": $([ -f "$RESULTS_DIR/output_audio.mp3" ] && echo "true" || echo "false")
}
EOF

echo "✅ Manifest created"
cat "$RESULTS_DIR/manifest.json"

echo "=== Export Complete ==="