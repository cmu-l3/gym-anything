#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Chapter Markers Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

LOG="/tmp/vlc_create_chapters_setup.log"
exec 1> >(tee -a "$LOG") 2>&1

# Create output directory
mkdir -p /home/ga/Videos/
mkdir -p /home/ga/Videos/chapters/
mkdir -p /tmp/chapter_temp/

echo "[$(date)] Creating source video for chapter task..."

# Generate a test video with 3 distinct visual sections (simulating lecture sections)
# Section 1: Blue (0:00-15:30 = 930s)
# Section 2: Green (15:30-30:45 = 915s) 
# Section 3: Red (30:45-45:00 = 855s)
# Total: ~45 minutes (2700s)

# For faster testing, scale down to 3 minutes (180s) with proportional sections:
# Section 1: Blue (0:00-0:54 = 54s)
# Section 2: Green (0:54-1:48 = 54s)
# Section 3: Red (1:48-3:00 = 72s)

echo "Generating 3-minute test video with distinct sections..."
ffmpeg -y \
  -f lavfi -i "color=c=blue:s=1280x720:d=54,format=yuv420p" \
  -f lavfi -i "color=c=green:s=1280x720:d=54,format=yuv420p" \
  -f lavfi -i "color=c=red:s=1280x720:d=72,format=yuv420p" \
  -f lavfi -i "anullsrc=r=44100:cl=stereo" \
  -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1:a=0[outv]" \
  -map "[outv]" -map "3:a" \
  -c:v libx264 -preset ultrafast -crf 28 \
  -c:a aac -b:a 128k \
  -t 180 \
  -pix_fmt yuv420p \
  /home/ga/Videos/lecture_recording.mp4 \
  2>&1 | grep -v "deprecated pixel format"

# Verify video was created
if [ ! -f /home/ga/Videos/lecture_recording.mp4 ]; then
    echo "ERROR: Failed to create lecture_recording.mp4"
    exit 1
fi

# Verify duration is approximately correct (175-185 seconds for 3min)
DURATION=$(ffprobe -v error -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 \
  /home/ga/Videos/lecture_recording.mp4 2>/dev/null || echo "0")

DURATION_INT=$(printf "%.0f" "$DURATION")

if [ "$DURATION_INT" -lt 170 ] || [ "$DURATION_INT" -gt 190 ]; then
    echo "WARNING: Video duration ($DURATION s) not in expected range (170-190s)"
else
    echo "✅ Source video created successfully"
fi

echo "Source video: $(ls -lh /home/ga/Videos/lecture_recording.mp4)"
echo "Duration: ${DURATION}s"

# Set permissions
chown -R ga:ga /home/ga/Videos/
chmod 644 /home/ga/Videos/lecture_recording.mp4

# Create a helper script that explains the task
cat > /home/ga/Videos/chapters/TASK_INSTRUCTIONS.txt << 'EOF'
TASK: Add Chapter Markers to Video

SOURCE: /home/ga/Videos/lecture_recording.mp4
OUTPUT: /home/ga/Videos/lecture_with_chapters.mp4

Required chapters:
1. 00:00:00 - "Introduction & Course Overview"
2. 00:00:54 - "Neural Network Fundamentals"  
3. 00:01:48 - "Practical Coding Examples"

Method 1 - Using ffmpeg:
--------------------------
# Create chapter metadata file
cat > /tmp/chapters_metadata.txt << 'METADATA'
;FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=54000
title=Introduction & Course Overview

[CHAPTER]
TIMEBASE=1/1000
START=54000
END=108000
title=Neural Network Fundamentals

[CHAPTER]
TIMEBASE=1/1000
START=108000
END=180000
title=Practical Coding Examples
METADATA

# Add chapters to video
ffmpeg -i /home/ga/Videos/lecture_recording.mp4 \
  -i /tmp/chapters_metadata.txt \
  -map_metadata 1 -codec copy \
  /home/ga/Videos/lecture_with_chapters.mp4

Method 2 - Using MP4Box (if available):
----------------------------------------
# Create simple chapter file
cat > /tmp/chapters_simple.txt << 'CHAPTERS'
00:00:00.000 Introduction & Course Overview
00:00:54.000 Neural Network Fundamentals
00:01:48.000 Practical Coding Examples
CHAPTERS

# Add chapters
MP4Box -chap /tmp/chapters_simple.txt \
  /home/ga/Videos/lecture_recording.mp4 \
  -out /home/ga/Videos/lecture_with_chapters.mp4

Verify chapters:
----------------
ffprobe -v error -show_chapters -of json /home/ga/Videos/lecture_with_chapters.mp4

Test in VLC:
------------
vlc /home/ga/Videos/lecture_with_chapters.mp4
# Use Playback → Chapter menu to navigate
EOF

chown ga:ga /home/ga/Videos/chapters/TASK_INSTRUCTIONS.txt

# Launch VLC with the source video (so agent can see what they're working with)
echo "Launching VLC to display source video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused /home/ga/Videos/lecture_recording.mp4 > /tmp/vlc_chapters_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "WARNING: VLC failed to start (non-critical for this task)"
else
    if wait_for_window "VLC media player" 20; then
        # Click on center of the screen to select current desktop
        echo "Selecting desktop..."
        su - ga -c "DISPLAY=:1 xdotool mousemove 640 360 click 1" 2>/dev/null || true
        sleep 1
        
        # Focus window
        wid=$(get_vlc_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid" || true
        fi
        echo "✅ VLC launched successfully"
    fi
fi

echo ""
echo "=== Create Chapter Markers Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  Source video: /home/ga/Videos/lecture_recording.mp4"
echo "  Output video: /home/ga/Videos/lecture_with_chapters.mp4"
echo ""
echo "  Required chapters at:"
echo "    - 00:00:00 - 'Introduction & Course Overview'"
echo "    - 00:00:54 - 'Neural Network Fundamentals'"
echo "    - 00:01:48 - 'Practical Coding Examples'"
echo ""
echo "  Recommended approach:"
echo "    1. Open a terminal (from VLC or desktop)"
echo "    2. Use ffmpeg to add chapter metadata"
echo "    3. See /home/ga/Videos/chapters/TASK_INSTRUCTIONS.txt for details"
echo ""