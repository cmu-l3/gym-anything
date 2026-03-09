#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Sleep Timer Task ==="

# Kill any existing VLC instances to start clean
kill_vlc ga
sleep 1

# Ensure Videos directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Check if long ambient video already exists (for efficiency in repeated runs)
VIDEO_FILE="/home/ga/Videos/relaxing_thunderstorm.mp4"

if [ -f "$VIDEO_FILE" ]; then
    EXISTING_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null || echo "0")
    if (( $(echo "$EXISTING_DURATION > 10000" | bc -l) )); then
        echo "✅ Long video already exists (${EXISTING_DURATION}s), skipping generation"
    else
        echo "Existing video too short, regenerating..."
        rm -f "$VIDEO_FILE"
    fi
fi

# Generate a long ambient video (180 minutes / 10800 seconds) if not exists
if [ ! -f "$VIDEO_FILE" ]; then
    echo "Generating 180-minute ambient video (this may take 30-45 seconds)..."
    
    # Create a visually interesting ambient video with gradual color shifts
    # Using faster encoding settings for reasonable generation time
    ffmpeg -f lavfi \
        -i "color=c=0x1a1a3e:s=1280x720:r=1:d=10800" \
        -f lavfi \
        -i "sine=frequency=220:duration=10800" \
        -shortest \
        -c:v libx264 -preset ultrafast -crf 30 -g 60 \
        -c:a aac -b:a 48k \
        -movflags +faststart \
        -y "$VIDEO_FILE" \
        2>&1 | grep -E "time=|Duration:" || true
    
    # Verify creation
    if [ ! -f "$VIDEO_FILE" ]; then
        echo "ERROR: Failed to generate ambient video"
        exit 1
    fi
    
    FILE_SIZE=$(stat -c%s "$VIDEO_FILE" 2>/dev/null || stat -f%z "$VIDEO_FILE" 2>/dev/null || echo "0")
    FILE_SIZE_MB=$((FILE_SIZE / 1024 / 1024))
    echo "✅ Generated video: ${FILE_SIZE_MB} MB"
    
    # Set ownership
    chown ga:ga "$VIDEO_FILE"
fi

# Verify video properties
echo "Verifying video properties..."
VIDEO_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null || echo "0")
VIDEO_DURATION_MIN=$(echo "scale=1; $VIDEO_DURATION / 60" | bc)

if (( $(echo "$VIDEO_DURATION < 10000" | bc -l) )); then
    echo "ERROR: Video duration too short: ${VIDEO_DURATION}s"
    exit 1
fi

echo "✅ Video duration: ${VIDEO_DURATION_MIN} minutes"

# Clear any previous task results
rm -f /tmp/vlc_sleep_timer_*.txt
rm -f /tmp/vlc_sleep_timer_*.json
rm -f /tmp/vlc_process_info.txt
rm -f /tmp/vlc_command_history.txt
rm -f /tmp/bash_vlc_history.txt

# Create instruction file
cat > /home/ga/Desktop/SLEEP_TIMER_INSTRUCTIONS.txt <<'EOF'
=== VLC SLEEP TIMER TASK ===

GOAL: Configure VLC to play for exactly 45 minutes and then automatically quit.

VIDEO FILE: /home/ga/Videos/relaxing_thunderstorm.mp4
DURATION: 180 minutes (long ambient video)

REQUIREMENTS:
1. Play for exactly 45 minutes (2700 seconds)
2. VLC must automatically QUIT (close completely) after 45 minutes
3. Do NOT loop the video
4. Do NOT just pause - VLC should close completely

SOLUTION:
Use VLC command-line parameters:

  vlc --run-time=2700 --play-and-exit /home/ga/Videos/relaxing_thunderstorm.mp4

OR with cvlc (command-line VLC):

  cvlc --run-time=2700 --play-and-exit /home/ga/Videos/relaxing_thunderstorm.mp4

TESTING:
You can test with a shorter duration first (e.g., 30 seconds):

  vlc --run-time=30 --play-and-exit /home/ga/Videos/relaxing_thunderstorm.mp4

KEY PARAMETERS:
  --run-time=SECONDS    Play for specified duration then stop
  --play-and-exit       Quit VLC after playback stops
  
NOTE: VLC does not have an obvious GUI sleep timer - you must use command-line flags.

EOF

chown ga:ga /home/ga/Desktop/SLEEP_TIMER_INSTRUCTIONS.txt
chmod 644 /home/ga/Desktop/SLEEP_TIMER_INSTRUCTIONS.txt

echo "=== Configure Sleep Timer Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Video available: /home/ga/Videos/relaxing_thunderstorm.mp4 (180 minutes)"
echo "  2. Configure VLC to play for exactly 45 minutes (2700 seconds)"
echo "  3. VLC must automatically quit after 45 minutes"
echo "  4. Use command-line: vlc --run-time=2700 --play-and-exit /home/ga/Videos/relaxing_thunderstorm.mp4"
echo "  5. See /home/ga/Desktop/SLEEP_TIMER_INSTRUCTIONS.txt for details"
echo ""
echo "💡 Hint: VLC has no GUI sleep timer - use --run-time command-line flag"

exit 0