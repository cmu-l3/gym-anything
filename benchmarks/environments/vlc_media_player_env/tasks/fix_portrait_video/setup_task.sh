#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Portrait Video Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure required directories exist
mkdir -p /home/ga/Videos/corrected
chown -R ga:ga /home/ga/Videos/corrected

# Create portrait video if it doesn't exist
PORTRAIT_VIDEO="/home/ga/Videos/portrait_sample.mp4"

if [ ! -f "$PORTRAIT_VIDEO" ]; then
    echo "Creating portrait video sample (1080x1920, 30 seconds)..."
    
    # Create a portrait video with clear visual indicators
    # Using ffmpeg to generate a test pattern with text overlay
    su - ga -c "ffmpeg -f lavfi -i color=c=0x4A90E2:s=1080x1920:d=30:r=30 \
        -vf \"drawtext=text='PORTRAIT MODE':fontsize=120:fontcolor=white:x=(w-text_w)/2:y=200:box=1:boxcolor=black@0.5:boxborderw=10, \
             drawtext=text='9\\\\:16 RATIO':fontsize=80:fontcolor=yellow:x=(w-text_w)/2:y=400, \
             drawtext=text='1080x1920':fontsize=60:fontcolor=white:x=(w-text_w)/2:y=h-300, \
             drawbox=x=iw/2-150:y=ih/2-150:w=300:h=300:color=white:t=fill, \
             drawtext=text='CENTER':fontsize=50:fontcolor=black:x=(w-text_w)/2:y=(h-text_h)/2\" \
        -c:v libx264 -preset fast -pix_fmt yuv420p '$PORTRAIT_VIDEO' -y > /tmp/create_portrait_video.log 2>&1"
    
    if [ $? -eq 0 ] && [ -f "$PORTRAIT_VIDEO" ]; then
        echo "✅ Portrait video created successfully"
        ls -lh "$PORTRAIT_VIDEO"
        
        # Verify the video properties
        echo "Video properties:"
        ffprobe -v error -select_streams v:0 \
            -show_entries stream=width,height,duration,codec_name \
            -of default=noprint_wrappers=1 "$PORTRAIT_VIDEO" 2>/dev/null || echo "Could not probe video"
    else
        echo "ERROR: Failed to create portrait video"
        cat /tmp/create_portrait_video.log
        exit 1
    fi
else
    echo "Portrait video already exists: $PORTRAIT_VIDEO"
fi

# Remove any previous output to ensure clean state
rm -f /home/ga/Videos/corrected/portrait_corrected.mp4

# Launch VLC without opening any file (agent needs to use Convert/Save menu)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_portrait_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_portrait_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "VLC window focused (ID: $wid)"
fi

# Give VLC a moment to fully initialize
sleep 2

echo "=== Fix Portrait Video Task Setup Complete ==="
echo ""
echo "📋 Task Overview:"
echo "  Source video: $PORTRAIT_VIDEO"
echo "  Properties: 1080x1920 pixels (9:16 portrait), ~30 seconds"
echo "  Target: 16:9 landscape format"
echo "  Output path: /home/ga/Videos/corrected/portrait_corrected.mp4"
echo ""
echo "📝 Instructions:"
echo "  1. Open Media → Convert/Save (or press Ctrl+R)"
echo "  2. Click 'Add' button and select: $PORTRAIT_VIDEO"
echo "  3. Click 'Convert/Save' button (NOT 'Play')"
echo "  4. In conversion dialog:"
echo "     - Select a profile or create custom profile"
echo "     - Configure video codec (H.264 recommended)"
echo "     - Apply video filters for aspect ratio correction:"
echo "       • Option A: Crop top/bottom to 16:9 (e.g., 1080x608 → scale to 1920x1080)"
echo "       • Option B: Add padding/canvas to sides (pillarbox)"
echo "       • Option C: Use geometry/transform filters"
echo "     - Set output resolution to 16:9 (e.g., 1920x1080, 1280x720)"
echo "  5. Set destination: /home/ga/Videos/corrected/portrait_corrected.mp4"
echo "  6. Click 'Start' and wait for conversion to complete"
echo ""
echo "💡 Hints:"
echo "  - Use Edit Profile → Video codec → Filters to add geometry transformations"
echo "  - Crop filter: Can specify pixels to remove from top/bottom/left/right"
echo "  - Canvas/padding filter: Can add borders to achieve target aspect ratio"
echo "  - Resolution tab: Set output width/height for 16:9 (1920x1080, 1280x720, etc.)"
echo ""