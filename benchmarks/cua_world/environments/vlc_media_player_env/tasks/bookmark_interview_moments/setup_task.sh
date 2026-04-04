#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Bookmark Interview Moments Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
mkdir -p /home/ga/Videos
mkdir -p /home/ga/.local/share/vlc
mkdir -p /home/ga/.config/vlc/bookmarks
chown -R ga:ga /home/ga/Videos /home/ga/.local/share/vlc /home/ga/.config/vlc

# Clear any existing bookmarks/media library to ensure clean state
rm -f /home/ga/.local/share/vlc/ml.xspf
rm -f /home/ga/.config/vlc/bookmarks/*.xspf
rm -f /home/ga/Videos/*.xspf

VIDEO_FILE="/home/ga/Videos/interview_migration_2024.mp4"

# Generate 12-minute interview video with visual cues at bookmark moments
echo "Generating interview video with visual cues..."

if ! command -v ffmpeg &> /dev/null; then
    echo "Installing ffmpeg..."
    sudo apt-get update -qq
    sudo apt-get install -y ffmpeg
fi

# Create video with:
# - 12 minutes (720 seconds) duration
# - Text overlays at key timestamps (2:15, 5:40, 9:20)
# - Visual cues to help agent identify bookmark moments
# - Timestamps visible to aid navigation

ffmpeg -y -f lavfi -i color=c=0x2c3e50:s=1280x720:d=720:r=30 \
    -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='Interview\\: Urban Migration Research':fontcolor=white:fontsize=36:x=(w-text_w)/2:y=50,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='Subject\\: Recent immigrant discussing experiences':fontcolor=0xecf0f1:fontsize=24:x=(w-text_w)/2:y=120,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='Time\\: %{pts\\:hms}':fontcolor=white:fontsize=28:x=(w-text_w)/2:y=650:box=1:boxcolor=black@0.6:boxborderw=8,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='🗣 ARRIVAL EXPERIENCE - First Day in City':fontcolor=yellow:fontsize=32:x=(w-text_w)/2:y=320:\
enable='between(t,130,145)',\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='[Subject gestures toward photograph on desk]':fontcolor=0xf39c12:fontsize=20:x=(w-text_w)/2:y=380:\
enable='between(t,130,145)',\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='🏠 HOUSING CHALLENGES - Discrimination & Search':fontcolor=yellow:fontsize=32:x=(w-text_w)/2:y=320:\
enable='between(t,335,350)',\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='[Subject expression becomes somber]':fontcolor=0xf39c12:fontsize=20:x=(w-text_w)/2:y=380:\
enable='between(t,335,350)',\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='🤝 COMMUNITY INTEGRATION - Finding Support':fontcolor=yellow:fontsize=32:x=(w-text_w)/2:y=320:\
enable='between(t,555,570)',\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='[Subject smiles discussing neighbors]':fontcolor=0xf39c12:fontsize=20:x=(w-text_w)/2:y=380:\
enable='between(t,555,570)',\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='General discussion':fontcolor=0x95a5a6:fontsize=22:x=(w-text_w)/2:y=340:\
enable='not(between(t,130,145)+between(t,335,350)+between(t,555,570))'" \
    -c:v libx264 -preset fast -crf 28 -pix_fmt yuv420p -t 720 "$VIDEO_FILE" \
    > /tmp/ffmpeg_interview_video.log 2>&1

# Verify video was created
if [ ! -f "$VIDEO_FILE" ]; then
    echo "ERROR: Failed to generate interview video"
    cat /tmp/ffmpeg_interview_video.log
    exit 1
fi

# Verify video duration
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null || echo "0")
if (( $(echo "$DURATION < 700" | bc -l) )); then
    echo "ERROR: Video duration too short: ${DURATION}s (expected ~720s)"
    exit 1
fi

echo "✅ Interview video created: $(ls -lh "$VIDEO_FILE" | awk '{print $5}')"
echo "   Duration: ${DURATION}s"

# Set ownership
chown ga:ga "$VIDEO_FILE"

# Launch VLC with the interview video
echo "Launching VLC with interview video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --extraintf rc --rc-host localhost:9999 '$VIDEO_FILE' > /tmp/vlc_bookmark_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_bookmark_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..10}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "RC interface ready"
        break
    fi
    echo "RC interface not ready, waiting... ($i/10)"
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Pause the video to give agent control
echo "Pausing video for agent control..."
sleep 2
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5

# Seek to beginning
su - ga -c "DISPLAY=:1 xdotool key ctrl+Home" || true
sleep 0.5

echo "=== Bookmark Interview Moments Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Video: /home/ga/Videos/interview_migration_2024.mp4 (12 minutes)"
echo "  2. Create bookmarks at three key moments (look for yellow text):"
echo "     - ~2:15 (135s): ARRIVAL EXPERIENCE"
echo "     - ~5:40 (340s): HOUSING CHALLENGES"
echo "     - ~9:20 (560s): COMMUNITY INTEGRATION"
echo "  3. Access bookmarks via: Playback → Custom Bookmarks → Manage"
echo "  4. Name bookmarks descriptively with relevant keywords"
echo "  5. Save/Apply bookmarks before closing"
echo ""
echo "💡 Navigation tips:"
echo "  - Shift+Right/Left: Jump 5 seconds"
echo "  - Ctrl+Right/Left: Jump 1 minute"
echo "  - Click timeline for rough seeking"