#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Sync Mistimed Subtitles Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Define paths
VIDEO_DIR="/home/ga/Videos/subtitle_sync_test"
VIDEO_FILE="${VIDEO_DIR}/test_video.mp4"
SUBTITLE_FILE="${VIDEO_DIR}/test_subtitles.srt"
INSTRUCTIONS_FILE="${VIDEO_DIR}/INSTRUCTIONS.txt"
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"

# Create directory
mkdir -p "${VIDEO_DIR}"
chown -R ga:ga "${VIDEO_DIR}"

# Generate a 30-second test video with visual timing markers
echo "Generating test video with timing markers..."
su - ga -c "ffmpeg -f lavfi -i color=c=blue:s=1280x720:d=30 \
  -vf \"drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='Subtitle Sync Test Video':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=100,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='Watch for subtitle timing':fontcolor=yellow:fontsize=32:x=(w-text_w)/2:y=300,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='Time\\: %{pts\\:hms}':fontcolor=white:fontsize=36:x=(w-text_w)/2:y=500\" \
  -c:v libx264 -pix_fmt yuv420p -t 30 '${VIDEO_FILE}' -y" > /tmp/vlc_video_gen.log 2>&1

if [ ! -f "${VIDEO_FILE}" ]; then
    echo "ERROR: Failed to generate test video"
    cat /tmp/vlc_video_gen.log
    exit 1
fi

echo "✅ Test video generated: ${VIDEO_FILE}"

# Generate subtitle file with intentional -2.5 second offset
# Subtitles are timed to appear 2.5 seconds BEFORE they should
# This simulates the common problem of "early" subtitles
cat > "${SUBTITLE_FILE}" << 'EOF'
1
00:00:00,500 --> 00:00:03,000
[This subtitle appears at 0.5s but should appear at 3.0s]

2
00:00:05,500 --> 00:00:08,000
If you're reading this at 5.5 seconds...

3
00:00:10,500 --> 00:00:13,000
...then the subtitles are NOT synchronized!

4
00:00:15,500 --> 00:00:18,000
These should appear at 18.0 seconds, not 15.5s.

5
00:00:20,500 --> 00:00:23,000
Fix by adding +2.5 second delay!

6
00:00:25,500 --> 00:00:28,000
Press H key 50 times, or use Track Synchronization menu.
EOF

chown ga:ga "${SUBTITLE_FILE}"
echo "✅ Subtitle file created with -2.5s offset: ${SUBTITLE_FILE}"

# Reset VLC subtitle delay settings to ensure clean slate
echo "Resetting VLC subtitle configuration..."
if [ -f "${VLC_CONFIG}" ]; then
    # Remove any existing subtitle delay settings
    su - ga -c "sed -i '/^sub-fps=/d' '${VLC_CONFIG}'" || true
    su - ga -c "sed -i '/^sub-delay=/d' '${VLC_CONFIG}'" || true
    su - ga -c "sed -i '/^spu-delay=/d' '${VLC_CONFIG}'" || true
    su - ga -c "sed -i '/^audio-desync=/d' '${VLC_CONFIG}'" || true
    echo "Cleared existing subtitle delay settings"
else
    echo "VLC config not found, will be created on first run"
fi

# Ensure VLC config directory exists
mkdir -p "$(dirname ${VLC_CONFIG})"
chown -R ga:ga /home/ga/.config/vlc/ || true

# Create instruction file for the agent
cat > "${INSTRUCTIONS_FILE}" << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║              SUBTITLE SYNCHRONIZATION TASK                      ║
╚════════════════════════════════════════════════════════════════╝

PROBLEM:
The subtitles for this video appear approximately 2.5 seconds TOO EARLY.
This means you see subtitle text BEFORE the corresponding moment in the video,
which spoils the content and ruins the viewing experience.

YOUR GOAL:
Fix the subtitle timing so they sync properly with the video.

DIAGNOSIS:
- Subtitles appearing TOO EARLY → Need POSITIVE delay
- The offset needed is approximately +2.5 seconds (+2500ms)

SOLUTION METHODS:

Method 1 - Keyboard Hotkeys (Fastest):
  • Press 'H' key to increase subtitle delay (+50ms per press)
  • Press 'G' key to decrease subtitle delay (-50ms per press)
  • Need ~50 presses of 'H' for +2500ms
  • Or use Shift+H for faster adjustment

Method 2 - Track Synchronization Menu (Recommended):
  • Open: Tools → Track Synchronization (or Ctrl+Shift+S)
  • Find: "Subtitle track synchronization" section
  • Adjust slider or type: +2500 milliseconds
  • Click OK or Close to apply

Method 3 - Preferences (Most Precise):
  • Open: Tools → Preferences
  • Click: "All" (Show all settings) at bottom left
  • Navigate: Input / Codecs → Subtitle codecs → Subtitles
  • Set: Subtitle delay to 2500000 microseconds
  • Save preferences

VERIFICATION:
The setting should persist in VLC configuration file after you close VLC.

KEY CONCEPT:
Positive delay = Subtitles appear LATER (fixes early subtitles)
Negative delay = Subtitles appear EARLIER (would make problem worse!)

Files:
  Video: /home/ga/Videos/subtitle_sync_test/test_video.mp4
  Subtitles: /home/ga/Videos/subtitle_sync_test/test_subtitles.srt
EOF

chown ga:ga "${INSTRUCTIONS_FILE}"
echo "✅ Instructions created: ${INSTRUCTIONS_FILE}"

# Launch VLC with video and subtitle file loaded
echo "Launching VLC with video and subtitles..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc \
  --avcodec-hw=none \
  --no-video-title-show \
  --sub-file='${SUBTITLE_FILE}' \
  --loop \
  '${VIDEO_FILE}' \
  > /tmp/vlc_subtitle_sync_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_subtitle_sync_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    cat /tmp/vlc_subtitle_sync_task.log
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 640 360 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "✅ VLC window focused (ID: $wid)"
else
    echo "⚠️ Could not get VLC window ID"
fi

# Wait for video to start playing
sleep 2

echo ""
echo "════════════════════════════════════════════════════════════"
echo "=== Sync Mistimed Subtitles Task Setup Complete ==="
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "  1. VLC is now playing a video with mistimed subtitles"
echo "  2. Notice: Subtitles appear ~2.5 seconds TOO EARLY"
echo "  3. Fix the timing by adjusting subtitle delay to +2.5s"
echo ""
echo "🎯 SOLUTION OPTIONS:"
echo "  Option A: Press 'H' key repeatedly (~50 times for +2.5s)"
echo "  Option B: Tools → Track Synchronization → Set to +2500ms"
echo "  Option C: Tools → Preferences → All → Subtitle delay"
echo ""
echo "📁 FILES:"
echo "  Video: ${VIDEO_FILE}"
echo "  Subtitles: ${SUBTITLE_FILE}"
echo "  Instructions: ${INSTRUCTIONS_FILE}"
echo ""
echo "⏱️  Expected time: 60-90 seconds"
echo "════════════════════════════════════════════════════════════"