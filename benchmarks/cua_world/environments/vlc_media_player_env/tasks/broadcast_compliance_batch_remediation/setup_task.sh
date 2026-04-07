#!/bin/bash
# Setup script for broadcast_compliance_batch_remediation task
# Creates 4 media files, each with a different broadcast standard violation
set -e

source /workspace/scripts/task_utils.sh

echo "Setting up broadcast_compliance_batch_remediation task..."

kill_vlc

# Create directories
mkdir -p /home/ga/Videos/qc_flagged
mkdir -p /home/ga/Videos/broadcast_ready
mkdir -p /home/ga/Documents

# File 1: Wrong framerate (30fps instead of 25fps PAL)
# Everything else compliant: 1920x1080, H.264, stereo AAC 48kHz
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=20" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=20" \
  -c:v libx264 -preset ultrafast -b:v 5M \
  -c:a aac -b:a 192k -ac 2 -ar 48000 \
  /home/ga/Videos/qc_flagged/news_segment_01.mp4 2>/dev/null

# File 2: Wrong resolution (720x480 NTSC SD instead of 1920x1080 Full HD)
# Everything else compliant: 25fps, H.264, stereo AAC 48kHz
ffmpeg -y -f lavfi -i "testsrc2=size=720x480:rate=25:duration=20" \
  -f lavfi -i "sine=frequency=523:sample_rate=48000:duration=20" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 192k -ac 2 -ar 48000 \
  /home/ga/Videos/qc_flagged/sports_highlight_02.mp4 2>/dev/null

# File 3: Mono audio instead of stereo
# Everything else compliant: 1920x1080, 25fps, H.264, 48kHz
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=25:duration=20" \
  -f lavfi -i "sine=frequency=659:sample_rate=48000:duration=20" \
  -c:v libx264 -preset ultrafast -b:v 5M \
  -c:a aac -b:a 128k -ac 1 -ar 48000 \
  /home/ga/Videos/qc_flagged/interview_03.mp4 2>/dev/null

# File 4: MPEG-2 codec in MPEG container instead of H.264/MP4
# Resolution and fps correct, but wrong codec and container
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=25:duration=20" \
  -f lavfi -i "sine=frequency=784:sample_rate=48000:duration=20" \
  -c:v mpeg2video -b:v 5M \
  -c:a mp2 -b:a 192k -ac 2 -ar 48000 \
  /home/ga/Videos/qc_flagged/documentary_04.mpg 2>/dev/null

# Create QC flags document
cat > /home/ga/Documents/qc_flags.txt << 'QCEOF'
=== Automated QC System Report ===
Date: 2026-03-08
Station: Regional Broadcast Network
Standard: EBU Technical Recommendation R128 / DVB Compliance

Flagged Files:
--------------
1. news_segment_01.mp4
   QC Status: FAILED
   Flag: Framerate non-compliance detected

2. sports_highlight_02.mp4
   QC Status: FAILED
   Flag: Resolution non-compliance detected

3. interview_03.mp4
   QC Status: FAILED
   Flag: Audio channel configuration non-compliance detected

4. documentary_04.mpg
   QC Status: FAILED
   Flag: Codec/container non-compliance detected

Target Broadcast Specifications:
- Resolution: 1920x1080 (Full HD)
- Framerate: 25fps (PAL)
- Video Codec: H.264 (AVC)
- Container: MP4
- Audio: Stereo (2 channels), AAC, 48kHz sample rate
- Minimum video bitrate: 4 Mbps

All remediated files must be placed in:
  /home/ga/Videos/broadcast_ready/

Compliance report required at:
  /home/ga/Documents/compliance_report.json
QCEOF

# Store ground truth for verifier
cat > /tmp/.broadcast_ground_truth.json << 'GTEOF'
{
  "files": {
    "news_segment_01.mp4": {"violation": "framerate", "original_fps": 30},
    "sports_highlight_02.mp4": {"violation": "resolution", "original_res": "720x480"},
    "interview_03.mp4": {"violation": "audio_channels", "original_channels": 1},
    "documentary_04.mpg": {"violation": "codec_container", "original_codec": "mpeg2video"}
  },
  "target_specs": {
    "width": 1920,
    "height": 1080,
    "fps": 25,
    "video_codec": "h264",
    "audio_codec": "aac",
    "audio_channels": 2,
    "audio_sample_rate": 48000
  }
}
GTEOF

chown -R ga:ga /home/ga/Videos/qc_flagged /home/ga/Videos/broadcast_ready /home/ga/Documents

# Launch VLC (no file loaded — agent must discover workflow)
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
sleep 2

echo "Setup complete for broadcast_compliance_batch_remediation task"
