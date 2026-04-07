#!/bin/bash
set -e
echo "=== Setting up lecture_speed_variants_study_package task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Videos/study_package/snapshots
mkdir -p /home/ga/Documents

# Fetch REAL data to be processed (using Big Buck Bunny as the proxy for the lecture video)
# We extract a precise 90-second clip, resize to 720p, and add a lecture watermark
echo "Downloading and preparing real source video..."
curl -L -s -o /tmp/source.mp4 "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"

# Use ffmpeg to prepare the lecture recording (90s, 720p, 30fps, standard h264/aac)
ffmpeg -y -i /tmp/source.mp4 -t 90 \
  -vf "scale=1280:720,drawtext=text='University E-Learning - Course DS-101':x=20:y=20:fontsize=32:fontcolor=white:box=1:boxcolor=black@0.5" \
  -c:v libx264 -preset fast -b:v 1500k \
  -c:a aac -b:a 128k -ar 44100 \
  /home/ga/Videos/lecture_recording.mp4 2>/dev/null

rm -f /tmp/source.mp4

# Generate the requirements document
cat > /home/ga/Documents/elearning_requirements.txt << 'REQEOF'
=== E-LEARNING STUDY PACKAGE REQUIREMENTS ===
Course: DS-101
Source: /home/ga/Videos/lecture_recording.mp4
Output Directory: /home/ga/Videos/study_package/

Students have requested multiple playback speeds and study aids. Generate the following deliverables:

1. SLOW VARIANT (0.75x speed)
   - Filename: lecture_075x.mp4
   - Video slowed to 0.75x speed (resulting duration ~120s)
   - Audio slowed to 0.75x speed (pitch must be preserved)
   - Must contain both video and audio streams

2. FAST VARIANT (1.5x speed)
   - Filename: lecture_150x.mp4
   - Video sped up to 1.5x speed (resulting duration ~60s)
   - Audio sped up to 1.5x speed (pitch must be preserved)
   - Must contain both video and audio streams

3. DOUBLE SPEED VARIANT (2.0x speed)
   - Filename: lecture_200x.mp4
   - Video sped up to 2.0x speed (resulting duration ~45s)
   - Audio sped up to 2.0x speed (pitch must be preserved)
   - Must contain both video and audio streams

4. KEYFRAME SNAPSHOTS
   - Extract one frame exactly every 15 seconds from the original video (at 0s, 15s, 30s, 45s, 60s, 75s, 90s)
   - Save to directory: /home/ga/Videos/study_package/snapshots/
   - Format: PNG
   - Naming: frame_00.png to frame_06.png (7 images total)

5. AUDIO-ONLY PODCAST
   - Filename: lecture_audio.mp3
   - Format: MP3, Stereo
   - Bitrate: 192 kbps
   - Contains the original unadjusted audio

6. PACKAGE MANIFEST
   - Filename: study_package.json (in /home/ga/Videos/study_package/)
   - Must be a valid JSON file documenting the 3 videos, the audio file, and the snapshots.
   - Include standard properties like duration and file size where applicable.
REQEOF

# Ensure proper permissions
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Launch VLC with the source video
echo "Starting VLC..."
su - ga -c "DISPLAY=:1 vlc --no-video-title-show /home/ga/Videos/lecture_recording.mp4 &" 2>/dev/null || true

# Wait for VLC to appear and maximize it
sleep 5
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="