#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Assess Digitization Quality Task ==="

kill_vlc ga
sleep 1

# Ensure required directories exist
VIDEO_DIR="/home/ga/Videos"
DOCS_DIR="/home/ga/Documents"
mkdir -p "$VIDEO_DIR" "$DOCS_DIR"
chown -R ga:ga "$VIDEO_DIR" "$DOCS_DIR"

echo "Generating test video simulating poor digitization..."

# Create base video with test pattern, moving elements, and audio
# This simulates a home video with varied content
ffmpeg -f lavfi -i testsrc=duration=30:size=640x480:rate=25 \
    -f lavfi -i sine=frequency=440:duration=30 \
    -filter_complex "\
        [0:v]drawtext=text='FAMILY BIRTHDAY PARTY 1995':x=(w-text_w)/2:y=h-50:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.5,\
        drawtext=text='Grandma Rose - Age 80':x=(w-text_w)/2:y=30:fontsize=20:fontcolor=yellow,\
        drawtext=text='Time\: %{pts\:hms}':x=10:y=10:fontsize=18:fontcolor=cyan,\
        drawtext=text='SPEAKING\: Hello everyone!':x=150:y=200:fontsize=16:fontcolor=white:enable='between(t,5,10)',\
        drawtext=text='SPEAKING\: Happy Birthday!':x=150:y=200:fontsize=16:fontcolor=white:enable='between(t,15,20)'[v]" \
    -map "[v]" -map 1:a \
    -pix_fmt yuv420p -c:v libx264 -preset fast -c:a aac -b:a 128k \
    /tmp/base_video.mp4 -y 2>/dev/null || {
        echo "ERROR: Failed to create base video"
        exit 1
    }

# Apply THREE intentional digitization issues:
# 1. Color oversaturation (PAL/NTSC color standard mismatch - very common)
#    - Boost saturation to 2.0 and adjust gamma slightly
# 2. Aspect ratio distortion (4:3 content incorrectly stretched to 16:9)
#    - Scale from 640x480 (4:3) to 854x480 (16:9) causing horizontal stretching
# 3. Progressive audio desync (VFR/CFR conversion error)
#    - Apply slight tempo reduction causing audio to progressively lag behind video

ffmpeg -i /tmp/base_video.mp4 \
    -vf "eq=saturation=2.0:gamma=0.93,scale=854:480:flags=bilinear,setdar=16/9" \
    -af "atempo=0.9985" \
    -c:v libx264 -preset fast -crf 23 -c:a aac -b:a 128k \
    "$VIDEO_DIR/family_recording.avi" -y 2>/dev/null || {
        echo "ERROR: Failed to create final video with issues"
        rm -f /tmp/base_video.mp4
        exit 1
    }

rm -f /tmp/base_video.mp4

chown ga:ga "$VIDEO_DIR/family_recording.avi"
chmod 644 "$VIDEO_DIR/family_recording.avi"

# Verify video was created
if [ ! -f "$VIDEO_DIR/family_recording.avi" ] || [ ! -s "$VIDEO_DIR/family_recording.avi" ]; then
    echo "ERROR: Failed to create test video"
    exit 1
fi

echo "✓ Test video created: $VIDEO_DIR/family_recording.avi"
echo "  - Contains 3 intentional digitization issues"
echo "  - Duration: 30 seconds"
echo "  - Issues: Color oversaturation, aspect ratio distortion, audio sync drift"

# Launch VLC with the digitized video
echo "Launching VLC with test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$VIDEO_DIR/family_recording.avi' > /tmp/vlc_digitization_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_digitization_task.log 2>/dev/null || true
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

# Let video play for a moment so agent can see initial state
sleep 2

echo "=== Assess Digitization Quality Task Setup Complete ==="
echo ""
echo "📝 INSTRUCTIONS FOR AGENT:"
echo "=========================================="
echo "You have received a digitized home video from a conversion service."
echo "The file plays, but something looks 'off'."
echo ""
echo "YOUR TASK:"
echo "1. Watch the video: /home/ga/Videos/family_recording.avi (now playing)"
echo "2. Assess THREE common digitization problems:"
echo "   a) Color Standard: Do colors look oversaturated/unnatural?"
echo "   b) Aspect Ratio: Are people/objects horizontally or vertically stretched?"
echo "   c) Audio Sync: Does audio match video? Check throughout - does sync worsen?"
echo ""
echo "3. Create report at: /home/ga/Documents/digitization_report.txt"
echo ""
echo "REPORT FORMAT:"
echo "  - Header: 'DIGITIZATION QUALITY ASSESSMENT REPORT'"
echo "  - For each issue: [YES/NO/UNCERTAIN] with observation"
echo "  - Recommendation: ACCEPTABLE / NEEDS_REPAIR / NEEDS_REDIGITIZATION"
echo "  - Reasoning for recommendation"
echo ""
echo "TIPS:"
echo "  - Try Video → Aspect Ratio menu to compare different ratios"
echo "  - Watch lips/speech timing at different points in video"
echo "  - Compare skin tones - do they look natural?"
echo "  - Video loops - watch multiple times to catch issues"
echo "=========================================="