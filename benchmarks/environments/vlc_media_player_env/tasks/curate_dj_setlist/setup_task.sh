#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up DJ Setlist Curation Task ==="

kill_vlc ga
sleep 1

# Create directories
TASK_DIR="/home/ga/Music/wedding_requests"
PLAYLIST_DIR="/home/ga/Music/playlists"
METADATA_DIR="/tmp/dj_task_metadata"

mkdir -p "$TASK_DIR"
mkdir -p "$PLAYLIST_DIR"
mkdir -p "$METADATA_DIR"
chown -R ga:ga "$TASK_DIR" "$PLAYLIST_DIR"

echo "Generating test audio files with varying bitrates..."

# High quality tracks (should be included) - 8 tracks
echo "Creating high-quality tracks (01-08)..."

# Track 01: 320 kbps MP3
ffmpeg -f lavfi -i "sine=frequency=440:duration=30" -b:a 320k \
  "$TASK_DIR/track_01_good.mp3" -y -loglevel error 2>&1
echo "320" > "$METADATA_DIR/track_01_good.mp3.bitrate"

# Track 02: 256 kbps MP3
ffmpeg -f lavfi -i "sine=frequency=523:duration=30" -b:a 256k \
  "$TASK_DIR/track_02_good.mp3" -y -loglevel error 2>&1
echo "256" > "$METADATA_DIR/track_02_good.mp3.bitrate"

# Track 03: 192 kbps MP3 (exactly at threshold)
ffmpeg -f lavfi -i "sine=frequency=659:duration=30" -b:a 192k \
  "$TASK_DIR/track_03_good.mp3" -y -loglevel error 2>&1
echo "192" > "$METADATA_DIR/track_03_good.mp3.bitrate"

# Track 04: FLAC (lossless - always high quality)
ffmpeg -f lavfi -i "sine=frequency=784:duration=30" -c:a flac \
  "$TASK_DIR/track_04_good.flac" -y -loglevel error 2>&1
echo "1411" > "$METADATA_DIR/track_04_good.flac.bitrate"  # Treat as CD quality

# Track 05: WAV (lossless - always high quality)
ffmpeg -f lavfi -i "sine=frequency=880:duration=30" -c:a pcm_s16le \
  "$TASK_DIR/track_05_good.wav" -y -loglevel error 2>&1
echo "1411" > "$METADATA_DIR/track_05_good.wav.bitrate"  # Treat as CD quality

# Track 06: 224 kbps MP3
ffmpeg -f lavfi -i "sine=frequency=1046:duration=30" -b:a 224k \
  "$TASK_DIR/track_06_good.mp3" -y -loglevel error 2>&1
echo "224" > "$METADATA_DIR/track_06_good.mp3.bitrate"

# Track 07: 256 kbps M4A
ffmpeg -f lavfi -i "sine=frequency=1174:duration=30" -c:a aac -b:a 256k \
  "$TASK_DIR/track_07_good.m4a" -y -loglevel error 2>&1
echo "256" > "$METADATA_DIR/track_07_good.m4a.bitrate"

# Track 08: 320 kbps MP3
ffmpeg -f lavfi -i "sine=frequency=1318:duration=30" -b:a 320k \
  "$TASK_DIR/track_08_good.mp3" -y -loglevel error 2>&1
echo "320" > "$METADATA_DIR/track_08_good.mp3.bitrate"

# Low quality tracks (should be excluded) - 7 tracks
echo "Creating low-quality tracks (09-15)..."

# Track 09: 128 kbps MP3 (common low quality)
ffmpeg -f lavfi -i "sine=frequency=440:duration=30" -b:a 128k \
  "$TASK_DIR/track_09_bad.mp3" -y -loglevel error 2>&1
echo "128" > "$METADATA_DIR/track_09_bad.mp3.bitrate"

# Track 10: 96 kbps MP3 (typical YouTube rip)
ffmpeg -f lavfi -i "sine=frequency=523:duration=30" -b:a 96k \
  "$TASK_DIR/track_10_bad.mp3" -y -loglevel error 2>&1
echo "96" > "$METADATA_DIR/track_10_bad.mp3.bitrate"

# Track 11: 64 kbps MP3 (very low)
ffmpeg -f lavfi -i "sine=frequency=659:duration=30" -b:a 64k \
  "$TASK_DIR/track_11_bad.mp3" -y -loglevel error 2>&1
echo "64" > "$METADATA_DIR/track_11_bad.mp3.bitrate"

# Track 12: 160 kbps MP3 (below threshold)
ffmpeg -f lavfi -i "sine=frequency=784:duration=30" -b:a 160k \
  "$TASK_DIR/track_12_bad.mp3" -y -loglevel error 2>&1
echo "160" > "$METADATA_DIR/track_12_bad.mp3.bitrate"

# Track 13: 112 kbps MP3
ffmpeg -f lavfi -i "sine=frequency=880:duration=30" -b:a 112k \
  "$TASK_DIR/track_13_bad.mp3" -y -loglevel error 2>&1
echo "112" > "$METADATA_DIR/track_13_bad.mp3.bitrate"

# Track 14: 80 kbps MP3
ffmpeg -f lavfi -i "sine=frequency=1046:duration=30" -b:a 80k \
  "$TASK_DIR/track_14_bad.mp3" -y -loglevel error 2>&1
echo "80" > "$METADATA_DIR/track_14_bad.mp3.bitrate"

# Track 15: 128 kbps MP3
ffmpeg -f lavfi -i "sine=frequency=1174:duration=30" -b:a 128k \
  "$TASK_DIR/track_15_bad.mp3" -y -loglevel error 2>&1
echo "128" > "$METADATA_DIR/track_15_bad.mp3.bitrate"

# Set permissions
chown -R ga:ga "$TASK_DIR"
chmod 644 "$TASK_DIR"/*

echo "✅ Task setup complete. 15 tracks created:"
echo "   - High-quality (≥192 kbps): tracks 01-08 (8 tracks)"
echo "   - Low-quality (<192 kbps): tracks 09-15 (7 tracks)"
echo ""
ls -lh "$TASK_DIR"

# Launch VLC
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_dj_setlist_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_dj_setlist_task.log
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

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== DJ Setlist Curation Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. Check audio quality of all files in /home/ga/Music/wedding_requests/"
echo "  2. Use Media Information (Ctrl+I) to check bitrate of each track"
echo "  3. Create a playlist containing ONLY tracks with bitrate ≥ 192 kbps"
echo "  4. Expected: 8 high-quality tracks (01-08)"
echo "  5. Save playlist as: /home/ga/Music/playlists/approved_setlist.xspf"
echo ""
echo "💡 Tip: Open Media → Open File, select tracks, press Ctrl+I to check info"