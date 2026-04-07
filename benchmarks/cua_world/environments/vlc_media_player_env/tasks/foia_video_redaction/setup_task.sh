#!/bin/bash
# Setup script for foia_video_redaction task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up FOIA Video Redaction Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

kill_vlc

# Create required directories
mkdir -p /home/ga/Videos/foia_release
mkdir -p /home/ga/Documents

echo "Generating body camera footage with distinct audio-visual segments..."

# Generate 6 segments of 20 seconds each with distinct visuals and audio frequencies
for i in {1..6}; do
  case $i in
    1) c="0x1a237e" ; txt="SCENE 1: ARRIVAL" ;;
    2) c="0x1b5e20" ; txt="SCENE 2: CONTACT" ;;
    3) c="0xb71c1c" ; txt="SCENE 3: WITNESS" ;;
    4) c="0xf57f17" ; txt="SCENE 4: INVESTIGATION" ;;
    5) c="0x4a148c" ; txt="SCENE 5: INFORMANT" ;;
    6) c="0x424242" ; txt="SCENE 6: DEPARTURE" ;;
  esac
  
  freq=$(( 330 + (i-1)*110 ))
  
  # Create 20s clip for each scene
  ffmpeg -y \
    -f lavfi -i "color=c=$c:s=1280x720:d=20:r=30" \
    -f lavfi -i "sine=frequency=$freq:sample_rate=48000:duration=20" \
    -vf "drawtext=text='$txt':x=100:y=360:fontsize=64:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10" \
    -c:v libx264 -preset ultrafast -b:v 2M \
    -c:a aac -b:a 128k \
    /tmp/foia_part${i}.mp4 2>/dev/null
done

# Concatenate the 6 segments into the full 120s master video
cat > /tmp/foia_concat.txt << EOF
file '/tmp/foia_part1.mp4'
file '/tmp/foia_part2.mp4'
file '/tmp/foia_part3.mp4'
file '/tmp/foia_part4.mp4'
file '/tmp/foia_part5.mp4'
file '/tmp/foia_part6.mp4'
EOF

ffmpeg -y -f concat -safe 0 -i /tmp/foia_concat.txt -c copy /home/ga/Videos/bodycam_incident_2024.mp4 2>/dev/null

# Clean up temp parts
rm -f /tmp/foia_part*.mp4 /tmp/foia_concat.txt

echo "Generating redaction schedule..."
# Create the redaction schedule document
cat > /home/ga/Documents/redaction_schedule.txt << 'SCHEDEOF'
========================================================================
FOIA REDACTION SCHEDULE
Case ID: FOIA-2024-0847
Source Media: bodycam_incident_2024.mp4 (Duration: 120s)
========================================================================

The Legal Department has reviewed the requested body camera footage and 
mandated the following redactions prior to public release.

REQUIRED REDACTIONS:

1. R1
   - Type: Audio mute (Video remains visible, audio track silenced)
   - Time Range: 0:40 to 1:00 (40s - 60s)
   - Reason: Witness identity protection (address and phone number spoken)
   - Legal Basis: State Code §38.2-610

2. R2
   - Type: Full excision (Segment completely cut and removed from video)
   - Time Range: 1:00 to 1:20 (60s - 80s)
   - Reason: Minor visible in frame during investigation
   - Legal Basis: FOIA Exemption 7(C)

3. R3
   - Type: Audio mute (Video remains visible, audio track silenced)
   - Time Range: 1:20 to 1:40 (80s - 100s)
   - Reason: Confidential informant voice recognition risk
   - Legal Basis: FOIA Exemption 7(D)

DELIVERABLES REQUIRED in /home/ga/Videos/foia_release/:
- evidence_audio_redacted.mp4 (Full 120s duration, only audio mutes applied)
- evidence_releasable.mp4 (Final ~100s video with both mutes AND the excision applied)
- redaction_log.json (Structured log of the 3 redactions)
- technical_properties.json (Technical metadata for both output videos)
========================================================================
SCHEDEOF

# Store ground truth for verification (hidden)
cat > /tmp/.foia_ground_truth.json << 'GTEOF'
{
  "case_id": "FOIA-2024-0847",
  "original_duration": 120.0,
  "releasable_duration": 100.0,
  "redactions": [
    {"id": "R1", "type": "audio_mute", "start": 40, "end": 60},
    {"id": "R2", "type": "full_excision", "start": 60, "end": 80},
    {"id": "R3", "type": "audio_mute", "start": 80, "end": 100}
  ]
}
GTEOF

# Ensure permissions
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Launch VLC with the raw video but don't auto-play
su - ga -c "DISPLAY=:1 vlc --no-video-title-show /home/ga/Videos/bodycam_incident_2024.mp4 &" 2>/dev/null || true
wait_for_window "VLC" 10

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="