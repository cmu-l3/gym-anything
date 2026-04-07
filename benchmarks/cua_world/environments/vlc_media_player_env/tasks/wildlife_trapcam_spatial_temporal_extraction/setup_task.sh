#!/bin/bash
echo "=== Setting up wildlife_trapcam_spatial_temporal_extraction task ==="

# Fallback for take_screenshot if task_utils.sh is missing
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || DISPLAY=:1 import -window root "$output_file" 2>/dev/null || true
    echo "Screenshot saved to $output_file"
}

# Source utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Videos/processed_events
mkdir -p /home/ga/Documents

# Prepare the source video
VIDEO_PATH="/home/ga/Videos/trapcam_raw_1080p.mp4"

echo "Generating realistic 4-quadrant trap camera video..."
# Generate a 3-minute video with 4 distinct colored quadrants and a timecode
# This creates a perfect testbed for spatial cropping without needing a 500MB download
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=180" \
    -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=180" \
    -vf "drawbox=x=0:y=0:w=960:h=540:color=darkgreen@0.5:t=fill,\
drawbox=x=960:y=0:w=960:h=540:color=darkblue@0.5:t=fill,\
drawbox=x=0:y=540:w=960:h=540:color=darkred@0.5:t=fill,\
drawbox=x=960:y=540:w=960:h=540:color=yellow@0.5:t=fill,\
drawtext=text='TRAP CAM A - NW':x=50:y=50:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.5,\
drawtext=text='TRAP CAM B - NE':x=1010:y=50:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.5,\
drawtext=text='TRAP CAM C - SW':x=50:y=590:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.5,\
drawtext=text='TRAP CAM D - SE':x=1010:y=590:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.5,\
drawtext=text='TCR\:%{pts\:hms}':x=850:y=500:fontsize=48:fontcolor=white:box=1:boxcolor=black@0.8" \
    -c:v libx264 -preset ultrafast -b:v 4M \
    -c:a aac -b:a 128k -ac 2 -ar 48000 \
    "$VIDEO_PATH" 2>/dev/null

# Create the field notes document
cat > /home/ga/Documents/field_notes.txt << 'EOF'
=== WILDLIFE TRAP CAMERA OBSERVATION LOG ===
Location: Sector 4 (Quad-feed composite view)
Date: 2026-03-10
File: trapcam_raw_1080p.mp4

Observations for Extraction:
- Event A: Subject enters the upper-left quadrant of the frame. Activity occurs between 0:15 and 0:25.
- Event B: Second subject observed in the lower-right quadrant. Activity occurs between 1:40 and 1:50.

Required Processing:
1. Extract the specified time segments for Event A and Event B.
2. Crop each video strictly to the specified quadrant (960x540 resolution).
3. Slow down the playback speed of the extracted clips to 0.5x (50% speed) for behavioral analysis.
4. Save as 'event_A_slow.mp4' and 'event_B_slow.mp4' in /home/ga/Videos/processed_events/
5. Create a JSON manifest at /home/ga/Documents/processing_log.json documenting original_start, original_end, crop_x, crop_y, crop_width, crop_height, and final_duration for each event.
EOF

# Ensure proper ownership
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Close any open VLC instances and open the environment ready for the user
pkill -f vlc 2>/dev/null || true
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
sleep 3

# Maximize the VLC window
DISPLAY=:1 wmctrl -r "VLC" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot showing setup
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="