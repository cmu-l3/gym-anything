#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Notification Sound Task ==="

kill_vlc ga
sleep 1

# Create notifications directory
NOTIFICATIONS_DIR="/home/ga/Music/notifications"
mkdir -p "${NOTIFICATIONS_DIR}"
chown -R ga:ga "${NOTIFICATIONS_DIR}"

VIDEOS_DIR="/home/ga/Videos"
MUSIC_DIR="/home/ga/Music"

# Create source media file with distinct audio segments
# We'll create a 60-second audio track with different tone patterns
echo "Generating source media with audio segments..."

# Create a simple audio file with recognizable patterns at different timestamps
# Using sine waves at different frequencies to create distinct segments
# Segment 1: 0-15s (440 Hz - A note)
# Segment 2: 15-30s (523 Hz - C note) <- THIS IS WHAT WE EXTRACT
# Segment 3: 30-45s (659 Hz - E note)
# Segment 4: 45-60s (784 Hz - G note)

ffmpeg -f lavfi -i "sine=frequency=440:duration=15" \
       -f lavfi -i "sine=frequency=523:duration=15" \
       -f lavfi -i "sine=frequency=659:duration=15" \
       -f lavfi -i "sine=frequency=784:duration=15" \
       -filter_complex "[0:a][1:a][2:a][3:a]concat=n=4:v=0:a=1[outa]" \
       -map "[outa]" -ac 2 -ar 44100 -ab 192k \
       "${MUSIC_DIR}/source_audio_full.mp3" \
       -y 2>/dev/null || {
    echo "ERROR: Failed to generate source audio"
    exit 1
}

# Also create a video version with the audio (more realistic for extraction scenario)
ffmpeg -f lavfi -i "color=c=blue:s=1280x720:d=60" \
       -i "${MUSIC_DIR}/source_audio_full.mp3" \
       -c:v libx264 -preset ultrafast -c:a aac -shortest \
       "${VIDEOS_DIR}/source_media.mp4" \
       -y 2>/dev/null || {
    echo "ERROR: Failed to generate source video"
    exit 1
}

chown ga:ga "${VIDEOS_DIR}/source_media.mp4"
chown ga:ga "${MUSIC_DIR}/source_audio_full.mp3"

echo "✓ Source media created"

# Write task parameters to JSON file
cat > "${NOTIFICATIONS_DIR}/task_params.json" << EOF
{
  "source_file": "${VIDEOS_DIR}/source_media.mp4",
  "start_time": "00:00:17.0",
  "stop_time": "00:00:21.0",
  "duration": 4.0,
  "output_file": "${NOTIFICATIONS_DIR}/custom_notification.mp3",
  "max_file_size_kb": 500,
  "target_format": "mp3",
  "target_channels": 1,
  "target_bitrate_kbps": 96,
  "target_sample_rate": 44100
}
EOF

chown ga:ga "${NOTIFICATIONS_DIR}/task_params.json"

# Create instruction file for the agent
cat > "${NOTIFICATIONS_DIR}/TASK_INSTRUCTIONS.txt" << EOF
=== NOTIFICATION SOUND CREATION TASK ===

OBJECTIVE:
Extract a 4-second audio segment from a video and optimize it as a mobile notification sound.

SOURCE FILE:
  ${VIDEOS_DIR}/source_media.mp4

EXTRACT AUDIO FROM:
  Start: 00:00:17 (17 seconds)
  Duration: 4 seconds
  Stop: 00:00:21 (21 seconds)

OUTPUT FILE:
  ${NOTIFICATIONS_DIR}/custom_notification.mp3

REQUIREMENTS:
  ✓ Duration: exactly 4 seconds (±0.5s tolerance)
  ✓ Format: MP3
  ✓ File size: < 500 KB
  ✓ Audio: mono channel (1 channel)
  ✓ Sample rate: 44100 Hz or 22050 Hz
  ✓ Bitrate: 64-128 kbps (recommended: 96 kbps)

INSTRUCTIONS:
  1. Open VLC Media Player
  2. Go to: Media → Convert/Save (or press Ctrl+R)
  3. Click "Add" button and select: ${VIDEOS_DIR}/source_media.mp4
  4. Check "Show more options" checkbox
  5. Set Start time: 00:00:17
  6. Set Stop time: 00:00:21 (or Duration: 4 seconds)
  7. Click "Convert/Save" button at bottom
  8. In the Convert dialog:
     a. Click the wrench/tool icon to edit profile
     b. Set Encapsulation: MP3
     c. In Audio codec tab:
        - Codec: MP3
        - Bitrate: 96 kb/s
        - Channels: 1 (Mono)
        - Sample rate: 44100 Hz
     d. Save the profile
  9. Set destination file: ${NOTIFICATIONS_DIR}/custom_notification.mp3
  10. Click "Start" to begin conversion

ALTERNATIVE (Command line if GUI is difficult):
  cvlc "${VIDEOS_DIR}/source_media.mp4" \\
    --start-time=17 --stop-time=21 \\
    --sout='#transcode{acodec=mp3,ab=96,channels=1,samplerate=44100}:std{access=file,mux=mp3,dst=${NOTIFICATIONS_DIR}/custom_notification.mp3}' \\
    vlc://quit

VERIFICATION:
  - Check file exists: ls -lh ${NOTIFICATIONS_DIR}/custom_notification.mp3
  - Check duration: ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 ${NOTIFICATIONS_DIR}/custom_notification.mp3
  - Check file size: Should be under 500 KB
EOF

chown ga:ga "${NOTIFICATIONS_DIR}/TASK_INSTRUCTIONS.txt"

# Launch VLC (empty, agent will use Convert/Save)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_notification_task.log 2>&1 &"

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

echo "=== Create Notification Sound Task Setup Complete ==="
echo ""
echo "📝 Task Summary:"
echo "  Source: ${VIDEOS_DIR}/source_media.mp4"
echo "  Extract: 4 seconds starting at 00:00:17"
echo "  Output: ${NOTIFICATIONS_DIR}/custom_notification.mp3"
echo "  Format: MP3, mono, 96 kbps, 44.1kHz, < 500 KB"
echo ""
echo "  Instructions available at: ${NOTIFICATIONS_DIR}/TASK_INSTRUCTIONS.txt"
echo "  Use Media → Convert/Save (Ctrl+R) to begin"