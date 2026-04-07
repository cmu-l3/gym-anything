#!/bin/bash
# Setup script for retail_video_wall_vlm_orchestration task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up retail_video_wall_vlm_orchestration task ==="

date +%s > /tmp/task_start_time.txt

kill_vlc "ga"

# Create directories
mkdir -p /home/ga/Videos/promos
mkdir -p /home/ga/Documents

# Generate promo videos
echo "Generating promo videos..."

# Window promo: 10 seconds, Red tint
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=10" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=10" \
  -vf "colorchannelmixer=rr=2.0:gg=0.5:bb=0.5" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k -ac 2 \
  /home/ga/Videos/promos/window_promo.mp4 2>/dev/null

# Entrance promo: 10 seconds, Green tint
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=10" \
  -f lavfi -i "sine=frequency=660:sample_rate=48000:duration=10" \
  -vf "colorchannelmixer=rr=0.5:gg=2.0:bb=0.5" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k -ac 2 \
  /home/ga/Videos/promos/entrance_promo.mp4 2>/dev/null

# Checkout promo: 10 seconds, Blue tint
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=10" \
  -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=10" \
  -vf "colorchannelmixer=rr=0.5:gg=0.5:bb=2.0" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k -ac 2 \
  /home/ga/Videos/promos/checkout_promo.mp4 2>/dev/null

# Create spec document
cat > /home/ga/Documents/vlm_spec.txt << 'SPECEOF'
=== RETAIL VIDEO WALL VLM SPECIFICATION ===

Location: Flagship Store #102

Source Files (in /home/ga/Videos/promos/):
1. window_promo.mp4
2. entrance_promo.mp4
3. checkout_promo.mp4

Broadcast Channels (VLM):
- Channel Name: 'window'
  - Input: window_promo.mp4
  - Output: http://127.0.0.1:8081/window (mux=ts)
  - Audio: MUST BE STRIPPED (Video only)
  - Behavior: Loop continuously

- Channel Name: 'entrance'
  - Input: entrance_promo.mp4
  - Output: http://127.0.0.1:8082/entrance (mux=ts)
  - Audio: Keep intact (Video + Audio)
  - Behavior: Loop continuously

- Channel Name: 'checkout'
  - Input: checkout_promo.mp4
  - Output: http://127.0.0.1:8083/checkout (mux=ts)
  - Audio: MUST BE STRIPPED (Video only)
  - Behavior: Loop continuously

Deployment:
1. Save VLM configuration to: /home/ga/Documents/signage.vlm
2. Create launch script at: /home/ga/start_signage.sh
3. The script must use headless VLC ('cvlc') to load the .vlm file and run it in the background.
4. Execute the script so the streams are live.
SPECEOF

chown -R ga:ga /home/ga/Videos/promos /home/ga/Documents

# Take initial screenshot for evidence
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="