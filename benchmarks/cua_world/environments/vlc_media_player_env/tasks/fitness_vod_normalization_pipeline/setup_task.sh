#!/bin/bash
set -e
echo "=== Setting up fitness_vod_normalization_pipeline task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || true

kill_vlc || true

mkdir -p /home/ga/Videos/fitness_raw
mkdir -p /home/ga/Videos/normalized
mkdir -p /home/ga/Videos/deliverables
mkdir -p /home/ga/Documents

echo "Generating raw videos..."
# 01_warmup.mp4
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=5" \
  -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=5" \
  -c:v libx264 -preset ultrafast -b:v 2M -pix_fmt yuv420p \
  -c:a aac -b:a 128k -ar 44100 \
  /home/ga/Videos/fitness_raw/01_warmup.mp4 2>/dev/null

# 02_ready_transition.mp4
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=3" \
  -f lavfi -i "sine=frequency=523:sample_rate=44100:duration=3" \
  -c:v libx264 -preset ultrafast -b:v 2M -pix_fmt yuv420p \
  -c:a aac -b:a 128k -ar 44100 \
  /home/ga/Videos/fitness_raw/02_ready_transition.mp4 2>/dev/null

# 03_block_A.mov (Non-conforming)
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=60:duration=10" \
  -f lavfi -i "sine=frequency=659:sample_rate=48000:duration=10" \
  -c:v libx265 -preset ultrafast -b:v 4M -pix_fmt yuv420p \
  -c:a pcm_s16le -ar 48000 \
  /home/ga/Videos/fitness_raw/03_block_A.mov 2>/dev/null

# 04_rest_transition.mp4
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=3" \
  -f lavfi -i "sine=frequency=523:sample_rate=44100:duration=3" \
  -c:v libx264 -preset ultrafast -b:v 2M -pix_fmt yuv420p \
  -c:a aac -b:a 128k -ar 44100 \
  /home/ga/Videos/fitness_raw/04_rest_transition.mp4 2>/dev/null

# 05_block_B.mp4
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=10" \
  -f lavfi -i "sine=frequency=784:sample_rate=44100:duration=10" \
  -c:v libx264 -preset ultrafast -b:v 2M -pix_fmt yuv420p \
  -c:a aac -b:a 128k -ar 44100 \
  /home/ga/Videos/fitness_raw/05_block_B.mp4 2>/dev/null

# 06_cooldown.mkv (Non-conforming)
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=5" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=5" \
  -c:v libx264 -preset ultrafast -b:v 2M -pix_fmt yuv420p \
  -c:a ac3 -b:a 192k -ar 48000 \
  /home/ga/Videos/fitness_raw/06_cooldown.mkv 2>/dev/null

# Write the spec
cat > /home/ga/Documents/encoding_spec.txt << 'EOF'
=== FITNESS VOD PIPELINE SPECIFICATION ===
Output Requirements for Master File:
- Resolution: 1280x720 (720p)
- Framerate: 30 fps
- Video Codec: H.264 (AVC)
- Audio Codec: AAC
- Audio Sample Rate: 44100 Hz
- Container: MP4

Deliverables:
1. Normalize any non-conforming videos from fitness_raw/ and save them in normalized/ with .mp4 extensions.
2. Concatenate all 6 videos in sequence to deliverables/master_class.mp4.
3. Extract an audio-only copy of the concatenated video to deliverables/outdoor_audio.mp3 (192 kbps).
4. Create an M3U playlist at deliverables/studio_playlist.m3u containing the 6 segments in order.
5. Generate a JSON manifest at /home/ga/Documents/class_metadata.json with keys "total_duration_sec" and "sequence" (list of filenames).
EOF

chown -R ga:ga /home/ga/Videos /home/ga/Documents
date +%s > /tmp/task_start_time.txt

# Launch a terminal and VLC
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &" 2>/dev/null || true
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
sleep 3

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "Setup complete"