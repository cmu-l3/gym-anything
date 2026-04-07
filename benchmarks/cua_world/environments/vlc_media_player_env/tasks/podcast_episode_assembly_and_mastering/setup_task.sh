#!/bin/bash
# Setup script for podcast_episode_assembly_and_mastering task
# Creates raw audio components and a production specification
set -e

source /workspace/scripts/task_utils.sh

echo "Setting up podcast_episode_assembly_and_mastering task..."

kill_vlc

# Create directories
mkdir -p /home/ga/Music/raw_podcast
mkdir -p /home/ga/Music/podcast_output
mkdir -p /home/ga/Documents

# Create intro jingle (5 seconds, stereo, musical chord pattern)
ffmpeg -y \
  -f lavfi -i "sine=frequency=523.25:sample_rate=44100:duration=5" \
  -f lavfi -i "sine=frequency=659.25:sample_rate=44100:duration=5" \
  -filter_complex "[0:a][1:a]amerge=inputs=2,volume=0.8[aout]" \
  -map "[aout]" \
  -c:a pcm_s16le -ar 44100 -ac 2 \
  /home/ga/Music/raw_podcast/intro.wav 2>/dev/null

# Create main episode recording (60 seconds, stereo, varying tones simulating speech)
# Use a complex filter to create volume variation (simulating natural speech dynamics)
ffmpeg -y \
  -f lavfi -i "sine=frequency=220:sample_rate=44100:duration=60" \
  -f lavfi -i "sine=frequency=330:sample_rate=44100:duration=60" \
  -filter_complex "[0:a][1:a]amerge=inputs=2,volume='if(between(t,0,15),0.6,if(between(t,15,30),0.9,if(between(t,30,45),0.5,0.8)))':eval=frame[aout]" \
  -map "[aout]" \
  -c:a pcm_s16le -ar 44100 -ac 2 \
  /home/ga/Music/raw_podcast/episode_raw.wav 2>/dev/null

# Create outro music (5 seconds, stereo, descending tone)
ffmpeg -y \
  -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=5" \
  -f lavfi -i "sine=frequency=349.23:sample_rate=44100:duration=5" \
  -filter_complex "[0:a][1:a]amerge=inputs=2,volume=0.7,afade=t=out:st=3:d=2[aout]" \
  -map "[aout]" \
  -c:a pcm_s16le -ar 44100 -ac 2 \
  /home/ga/Music/raw_podcast/outro.wav 2>/dev/null

# Create production specification
cat > /home/ga/Documents/production_spec.txt << 'SPECEOF'
=== PRODUCTION SPECIFICATION ===
Show: The Finance Hour
Episode: 47 - Market Analysis
Season: 3

SOURCE COMPONENTS (in /home/ga/Music/raw_podcast/):
  intro.wav    - Opening jingle (5 seconds)
  episode_raw.wav - Main episode recording (60 seconds)
  outro.wav    - Closing music (5 seconds)

ASSEMBLY ORDER:
  1. intro.wav
  2. episode_raw.wav
  3. outro.wav

DELIVERABLES (save all to /home/ga/Music/podcast_output/):

  1. Master file: episode_47_master.wav
     - Format: WAV (PCM 16-bit)
     - Sample rate: 44100 Hz
     - Channels: Stereo
     - Content: Full assembled episode (intro + episode + outro)

  2. Distribution file: episode_47_dist.mp3
     - Format: MP3
     - Bitrate: 192 kbps
     - Channels: Stereo
     - Content: Full assembled episode (same as master)
     - ID3 Metadata:
         Title:  Episode 47: Market Analysis
         Artist: The Finance Hour
         Album:  Season 3
         Track:  47

  3. Highlight clip: episode_47_highlight.mp3
     - Format: MP3
     - Bitrate: 192 kbps
     - Content: 15-second excerpt from the RAW EPISODE recording
                starting at the 20-second mark (20s to 35s of episode_raw.wav)
     - Purpose: Social media promotional clip
SPECEOF

# Store ground truth for verifier
cat > /tmp/.podcast_ground_truth.json << 'GTEOF'
{
  "intro_duration": 5.0,
  "episode_duration": 60.0,
  "outro_duration": 5.0,
  "total_duration": 70.0,
  "highlight_start": 20.0,
  "highlight_duration": 15.0,
  "master_filename": "episode_47_master.wav",
  "dist_filename": "episode_47_dist.mp3",
  "highlight_filename": "episode_47_highlight.mp3",
  "id3_title": "Episode 47: Market Analysis",
  "id3_artist": "The Finance Hour",
  "id3_album": "Season 3",
  "id3_track": 47,
  "sample_rate": 44100,
  "channels": 2,
  "mp3_bitrate": 192000
}
GTEOF

chown -R ga:ga /home/ga/Music /home/ga/Documents

# Launch VLC (no file loaded)
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
sleep 2

echo "Setup complete for podcast_episode_assembly_and_mastering task"
