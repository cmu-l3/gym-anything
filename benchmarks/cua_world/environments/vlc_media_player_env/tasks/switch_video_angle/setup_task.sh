#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Switch Video Angle Task ==="

kill_vlc ga
sleep 1

# Create multi-angle concert video
VIDEO_DIR="/home/ga/Videos"
OUTPUT_FILE="$VIDEO_DIR/concert_multiangle.mkv"

echo "Creating multi-angle concert video..."

# Generate three different synthetic video tracks (3 colored patterns for easy visual distinction)
# Track 0: Wide view (blue background with moving circle)
ffmpeg -f lavfi -i "color=c=blue:s=1280x720:d=30:r=30" \
       -vf "drawtext=text='WIDE VIEW - Track 0':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=50:box=1:boxcolor=black@0.5:boxborderw=5,\
            drawbox=x=iw/2-50+50*sin(2*PI*t/5):y=ih/2-50+50*cos(2*PI*t/5):w=100:h=100:color=yellow:t=fill" \
       -pix_fmt yuv420p -c:v libx264 -preset fast -crf 22 -t 30 -y /tmp/track0.mp4 2>/dev/null

# Track 1: Vocalist close-up (red background with moving square)
ffmpeg -f lavfi -i "color=c=red:s=1280x720:d=30:r=30" \
       -vf "drawtext=text='VOCALIST CLOSEUP - Track 1':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=50:box=1:boxcolor=black@0.5:boxborderw=5,\
            drawbox=x=iw/2-75+100*cos(2*PI*t/3):y=ih/2-75:w=150:h=150:color=white:t=fill" \
       -pix_fmt yuv420p -c:v libx264 -preset fast -crf 22 -t 30 -y /tmp/track1.mp4 2>/dev/null

# Track 2: Drummer cam (green background with moving triangle)
ffmpeg -f lavfi -i "color=c=green:s=1280x720:d=30:r=30" \
       -vf "drawtext=text='DRUMMER CAM - Track 2':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=50:box=1:boxcolor=black@0.5:boxborderw=5,\
            drawbox=x=iw/2-60+80*sin(2*PI*t/4):y=ih/2-60+80*cos(2*PI*t/4):w=120:h=120:color=orange:t=fill" \
       -pix_fmt yuv420p -c:v libx264 -preset fast -crf 22 -t 30 -y /tmp/track2.mp4 2>/dev/null

# Generate simple audio track (shared across all video tracks)
ffmpeg -f lavfi -i "sine=frequency=440:duration=30" -c:a aac -b:a 128k -y /tmp/audio.aac 2>/dev/null

# Combine into multi-track MKV file
# Map all video streams and one audio stream
ffmpeg -i /tmp/track0.mp4 -i /tmp/track1.mp4 -i /tmp/track2.mp4 -i /tmp/audio.aac \
       -map 0:v -map 1:v -map 2:v -map 3:a \
       -c:v copy -c:a copy \
       -metadata:s:v:0 title="Wide Stage View" \
       -metadata:s:v:1 title="Vocalist Close-up" \
       -metadata:s:v:2 title="Drummer Camera" \
       -y "$OUTPUT_FILE" 2>/dev/null

# Cleanup temp files
rm -f /tmp/track*.mp4 /tmp/audio.aac

# Verify multi-track file was created
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Multi-angle concert video created: $OUTPUT_FILE"
    
    # Verify track count
    TRACK_COUNT=$(ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$OUTPUT_FILE" 2>/dev/null | wc -l)
    echo "Video tracks detected: $TRACK_COUNT"
    
    if [ "$TRACK_COUNT" -lt 2 ]; then
        echo "⚠️ Warning: Expected multiple video tracks, found $TRACK_COUNT"
    fi
else
    echo "✗ Failed to create multi-angle video"
    exit 1
fi

chown ga:ga "$OUTPUT_FILE" 2>/dev/null || true
chmod 644 "$OUTPUT_FILE" 2>/dev/null || true

# Launch VLC with the multi-track video
echo "Launching VLC with multi-angle video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$OUTPUT_FILE' > /tmp/vlc_video_track_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_video_track_task.log 2>/dev/null || true
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait for video to start playing
sleep 2

echo "=== Switch Video Angle Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing a multi-angle concert video"
echo "  2. Currently showing: Track 0 (Wide Stage View - BLUE background)"
echo "  3. Switch to Track 1 (Vocalist Close-up - RED background)"
echo "  4. Methods:"
echo "     a) Video → Video Track → Track 1"
echo "     b) Press Shift+V to cycle through tracks"
echo "     c) Restart VLC with --video-track-id=1 flag"
echo "  5. Verify: Track 1 should show RED background with 'VOCALIST CLOSEUP' text"