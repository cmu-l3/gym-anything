#!/bin/bash
# Setup script for vhs_archival_digitization_cleanup task
set -e

source /workspace/scripts/task_utils.sh || true

echo "=== Setting up VHS Archival Digitization task ==="

kill_vlc 2>/dev/null || true

# Record task start time (for anti-gaming timestamps)
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Videos/vhs_raw
mkdir -p /home/ga/Videos/archive_access
mkdir -p /home/ga/Documents

# 1. Create raw VHS capture 1 (10s, 720x480, stereo)
ffmpeg -y -f lavfi -i "testsrc2=size=720x480:rate=30:duration=10" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=10" \
  -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=10" \
  -filter_complex "[0:v]drawtext=text='1992 GRADUATION':x=50:y=50:fontsize=36:fontcolor=white[vout];[1:a][2:a]amerge=inputs=2[aout]" \
  -map "[vout]" -map "[aout]" \
  -c:v libx264 -preset ultrafast -b:v 2M -flags +ilme+ildct \
  -c:a aac -b:a 128k -ac 2 \
  /home/ga/Videos/vhs_raw/tape_1992_grad.mkv 2>/dev/null

# 2. Create raw VHS capture 2
ffmpeg -y -f lavfi -i "testsrc2=size=720x480:rate=30:duration=10" \
  -f lavfi -i "sine=frequency=330:sample_rate=48000:duration=10" \
  -f lavfi -i "sine=frequency=660:sample_rate=48000:duration=10" \
  -filter_complex "[0:v]drawtext=text='1994 PICNIC':x=50:y=50:fontsize=36:fontcolor=white[vout];[1:a][2:a]amerge=inputs=2[aout]" \
  -map "[vout]" -map "[aout]" \
  -c:v libx264 -preset ultrafast -b:v 2M -flags +ilme+ildct \
  -c:a aac -b:a 128k -ac 2 \
  /home/ga/Videos/vhs_raw/tape_1994_picnic.mkv 2>/dev/null

# 3. Create raw VHS capture 3
ffmpeg -y -f lavfi -i "testsrc2=size=720x480:rate=30:duration=10" \
  -f lavfi -i "sine=frequency=550:sample_rate=48000:duration=10" \
  -f lavfi -i "sine=frequency=1100:sample_rate=48000:duration=10" \
  -filter_complex "[0:v]drawtext=text='1995 STORM':x=50:y=50:fontsize=36:fontcolor=white[vout];[1:a][2:a]amerge=inputs=2[aout]" \
  -map "[vout]" -map "[aout]" \
  -c:v libx264 -preset ultrafast -b:v 2M -flags +ilme+ildct \
  -c:a aac -b:a 128k -ac 2 \
  /home/ga/Videos/vhs_raw/tape_1995_storm.mkv 2>/dev/null

# Create archive catalog CSV
cat > /home/ga/Documents/archive_catalog.csv << 'CSVEOF'
filename,title_tag
tape_1992_grad.mkv,1992 Graduation Ceremony
tape_1994_picnic.mkv,1994 Company Picnic
tape_1995_storm.mkv,1995 Winter Storm
CSVEOF

chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Launch VLC (empty instance, preparing the agent environment)
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true

# Wait for VLC to be visible and maximize it
sleep 3
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="