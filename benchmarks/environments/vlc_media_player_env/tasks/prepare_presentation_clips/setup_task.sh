#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Prepare Presentation Clips Task ==="

kill_vlc ga
sleep 1

TASK_DIR="/workspace/tasks/prepare_presentation_clips"
VIDEOS_DIR="/home/ga/Videos/presentation"
OUTPUT_DIR="/home/ga/Documents/presentation"

# Create directories
mkdir -p "$VIDEOS_DIR"
mkdir -p "$OUTPUT_DIR"
chmod -R 755 "$VIDEOS_DIR" "$OUTPUT_DIR"
chown -R ga:ga "$VIDEOS_DIR" "$OUTPUT_DIR"

# Generate three sample videos with different lengths for the presentation
echo "Generating sample presentation videos..."

# Video 1: Animal behavior clip (30 seconds - need at least 15s)
echo "  Creating animal_foraging.mp4 (30s)..."
ffmpeg -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 \
    -vf "drawtext=text='Animal Foraging Behavior':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=black@0.5:boxborderw=5" \
    -f lavfi -i sine=frequency=440:duration=30 \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
    -c:a aac -b:a 128k \
    "$VIDEOS_DIR/animal_foraging.mp4" -y 2>/dev/null

# Video 2: Research footage clip (120 seconds = 2 minutes - need at least 90s)
echo "  Creating colony_interaction.mp4 (120s)..."
ffmpeg -f lavfi -i testsrc=duration=120:size=1920x1080:rate=30 \
    -vf "drawtext=text='Colony Interaction Study':fontsize=60:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=black@0.5:boxborderw=5" \
    -f lavfi -i sine=frequency=523:duration=120 \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
    -c:a aac -b:a 128k \
    "$VIDEOS_DIR/colony_interaction.mp4" -y 2>/dev/null

# Video 3: Field observation clip (90 seconds - need at least 45s)
echo "  Creating migration_pattern.mp4 (90s)..."
ffmpeg -f lavfi -i testsrc=duration=90:size=1280x720:rate=30 \
    -vf "drawtext=text='Migration Patterns':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=black@0.5:boxborderw=5" \
    -f lavfi -i sine=frequency=329:duration=90 \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
    -c:a aac -b:a 128k \
    "$VIDEOS_DIR/migration_pattern.mp4" -y 2>/dev/null

chown -R ga:ga "$VIDEOS_DIR"

# Verify files were created
echo "Verifying video files..."
for video in animal_foraging.mp4 colony_interaction.mp4 migration_pattern.mp4; do
    if [ ! -f "$VIDEOS_DIR/$video" ]; then
        echo "ERROR: Failed to create $video"
        exit 1
    fi
    size=$(stat -c%s "$VIDEOS_DIR/$video" 2>/dev/null || stat -f%z "$VIDEOS_DIR/$video" 2>/dev/null)
    size_kb=$((size / 1024))
    echo "  ✓ $video (${size_kb} KB)"
done

# Create task instruction file for the agent
cat > "$OUTPUT_DIR/task_instructions.txt" << 'EOF'
PRESENTATION CLIP PREPARATION TASK
===================================

SCENARIO:
You are helping a biology professor prepare video clips for a conference talk.
Each video needs to start at a SPECIFIC TIMESTAMP (not from the beginning),
so the presenter can show only the relevant parts without scrubbing through footage.

GOAL:
Create a VLC playlist in XSPF format with precise start times for each video.

REQUIRED PLAYLIST CONFIGURATION:
--------------------------------
File location: /home/ga/Documents/presentation/talk_clips.xspf
Format: XSPF (VLC advanced playlist format - NOT M3U)

VIDEOS TO INCLUDE (in this exact order):
-----------------------------------------
1. /home/ga/Videos/presentation/animal_foraging.mp4
   START AT: 15 seconds (skip intro)

2. /home/ga/Videos/presentation/colony_interaction.mp4
   START AT: 90 seconds (1 minute 30 seconds - jump to key behavior)

3. /home/ga/Videos/presentation/migration_pattern.mp4
   START AT: 45 seconds (skip title sequence)

REQUIREMENTS:
-------------
✓ Each video must start at the specified timestamp, NOT from beginning
✓ Playlist must be saved in XSPF format (supports start-time parameters)
✓ All 3 videos in correct order
✓ File must be valid XML

HOW TO CREATE (Recommended Method):
------------------------------------
1. Open VLC
2. Go to: Media → Open File (Advanced) or Ctrl+Shift+O
3. For EACH video:
   a. Click "Add" and select the video file
   b. Check "Show more options" at bottom
   c. In "Start time" field, enter the seconds value (15, 90, or 45)
   d. Click "Play" or "Enqueue" to add to playlist
4. After adding all 3 videos:
   a. Go to: Media → Save Playlist to File
   b. Choose location: /home/ga/Documents/presentation/talk_clips.xspf
   c. IMPORTANT: Select format "XSPF playlist (*.xspf)" NOT M3U
   d. Click Save

ALTERNATIVE METHOD (Advanced):
-------------------------------
You can also manually create/edit the XSPF file with proper XML structure
including <vlc:option>start-time=XX</vlc:option> tags.

VERIFICATION:
-------------
Your playlist will be checked for:
✓ Valid XSPF XML format
✓ Correct file paths for all 3 videos
✓ Correct start times (±2 second tolerance):
  - Video 1: 15s
  - Video 2: 90s  
  - Video 3: 45s
✓ Proper VLC extension format

Good luck! This is a real-world workflow used by presenters worldwide.
EOF

chown ga:ga "$OUTPUT_DIR/task_instructions.txt"

# Launch VLC (empty, agent will use it to create playlist)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_presentation_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
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

echo "=== Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "  Location: $OUTPUT_DIR/task_instructions.txt"
echo ""
echo "  QUICK SUMMARY:"
echo "  - Create XSPF playlist at: /home/ga/Documents/presentation/talk_clips.xspf"
echo "  - Add 3 videos from: /home/ga/Videos/presentation/"
echo "  - Set start times: 15s, 90s, 45s respectively"
echo "  - Use: Media → Open File (Advanced) to set start times"
echo "  - Save as XSPF format (not M3U)"
echo ""
echo "Videos available:"
ls -lh "$VIDEOS_DIR"