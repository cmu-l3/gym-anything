#!/bin/bash
echo "=== Setting up streaming_loudness_compliance task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Music/ep_masters
mkdir -p /home/ga/Music/normalized_delivery/{spotify,apple,youtube}
mkdir -p /home/ga/Documents

# Generate source audio tracks with specific loudness profiles
# 0dBFS sine wave is approx -3 LUFS.
# Track 1: -8 LUFS (volume=-5dB)
ffmpeg -y -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=10" \
    -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=10" \
    -filter_complex "[0:a][1:a]amerge=inputs=2,volume=-5dB[aout]" -map "[aout]" \
    -c:a pcm_s16le /home/ga/Music/ep_masters/track_01_overture.wav 2>/dev/null

# Track 2: -22 LUFS (volume=-19dB)
ffmpeg -y -f lavfi -i "sine=frequency=330:sample_rate=48000:duration=10" \
    -f lavfi -i "sine=frequency=660:sample_rate=48000:duration=10" \
    -filter_complex "[0:a][1:a]amerge=inputs=2,volume=-19dB[aout]" -map "[aout]" \
    -c:a pcm_s16le /home/ga/Music/ep_masters/track_02_nocturne.wav 2>/dev/null

# Track 3: -12 LUFS (volume=-9dB)
ffmpeg -y -f lavfi -i "sine=frequency=220:sample_rate=48000:duration=10" \
    -filter_complex "[0:a]volume=-9dB[aout]" -map "[aout]" \
    -ac 2 -c:a pcm_s16le /home/ga/Music/ep_masters/track_03_pulse.wav 2>/dev/null

# Track 4: -28 LUFS (volume=-25dB)
ffmpeg -y -f lavfi -i "sine=frequency=550:sample_rate=48000:duration=10" \
    -filter_complex "[0:a]volume=-25dB[aout]" -map "[aout]" \
    -ac 2 -c:a pcm_s16le /home/ga/Music/ep_masters/track_04_finale.wav 2>/dev/null

# Create specifications document
cat > /home/ga/Documents/platform_loudness_specs.json << 'EOF'
{
  "project": "Synthesis EP",
  "description": "Platform-specific loudness targets for digital distribution. All outputs must go to /home/ga/Music/normalized_delivery/<platform>/",
  "platforms": {
    "spotify": {
      "target_lufs": -14.0,
      "format_requirements": {
        "codec": "MP3",
        "bitrate": "320kbps",
        "sample_rate": 44100
      },
      "output_extension": ".mp3"
    },
    "apple_music": {
      "target_lufs": -16.0,
      "format_requirements": {
        "codec": "AAC",
        "bitrate": "256kbps",
        "sample_rate": 44100
      },
      "output_extension": ".m4a"
    },
    "youtube_music": {
      "target_lufs": -13.0,
      "format_requirements": {
        "codec": "Opus",
        "bitrate": "128kbps",
        "sample_rate": 48000
      },
      "output_extension": ".opus"
    }
  },
  "report_template": {
    "ep_title": "Synthesis EP",
    "tracks": [
      {
        "source_file": "track_01_overture.wav",
        "source_lufs": -8.1,
        "platforms": {
          "spotify": {
            "target_lufs": -14.0,
            "achieved_lufs": -14.0,
            "output_file": "spotify/track_01_overture.mp3"
          }
        }
      }
    ]
  }
}
EOF

# Ensure permissions
chown -R ga:ga /home/ga/Music /home/ga/Documents

# Launch VLC in background
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
sleep 3
DISPLAY=:1 wmctrl -r "VLC" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="