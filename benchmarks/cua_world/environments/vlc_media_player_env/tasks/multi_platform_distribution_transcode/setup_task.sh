#!/bin/bash
# Setup script for multi_platform_distribution_transcode task
# Creates a master video and platform specification document
set -e

source /workspace/scripts/task_utils.sh

echo "Setting up multi_platform_distribution_transcode task..."

kill_vlc

# Create directories
mkdir -p /home/ga/Videos/deliverables
mkdir -p /home/ga/Documents

# Create a high-quality master video (60 seconds, 1920x1080, H.264)
# Use complex test source with multiple visual elements for realistic content
ffmpeg -y \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=60" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=60" \
  -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=60" \
  -filter_complex "[1:a][2:a]amerge=inputs=2[aout]" \
  -map 0:v -map "[aout]" \
  -c:v libx264 -preset medium -b:v 8M -pix_fmt yuv420p \
  -c:a aac -b:a 256k -ac 2 -ar 48000 \
  /home/ga/Videos/master_content.mp4 2>/dev/null

# Create platform specifications document
cat > /home/ga/Documents/platform_specs.json << 'SPECEOF'
{
  "project": "Q1 2026 Content Distribution Package",
  "source_file": "/home/ga/Videos/master_content.mp4",
  "output_directory": "/home/ga/Videos/deliverables/",
  "platforms": {
    "broadcast": {
      "filename": "broadcast_delivery.mp4",
      "container": "mp4",
      "video_codec": "h264",
      "resolution": "1920x1080",
      "framerate": 25,
      "video_bitrate_kbps": 5000,
      "audio_codec": "aac",
      "audio_channels": 2,
      "audio_sample_rate": 48000,
      "audio_bitrate_kbps": 192,
      "notes": "PAL broadcast standard. Must be exactly 25fps."
    },
    "mobile": {
      "filename": "mobile_delivery.mp4",
      "container": "mp4",
      "video_codec": "h264",
      "resolution": "640x360",
      "framerate": 30,
      "video_bitrate_kbps": 1000,
      "audio_codec": "aac",
      "audio_channels": 1,
      "audio_sample_rate": 44100,
      "audio_bitrate_kbps": 96,
      "notes": "Low-bandwidth mobile delivery. Mono audio to reduce size."
    },
    "web_streaming": {
      "filename": "web_delivery.mkv",
      "container": "mkv",
      "video_codec": "h264",
      "resolution": "1280x720",
      "framerate": 30,
      "video_bitrate_kbps": 3000,
      "audio_codec": "aac",
      "audio_channels": 2,
      "audio_sample_rate": 44100,
      "audio_bitrate_kbps": 128,
      "notes": "720p web streaming in MKV container."
    },
    "audio_only": {
      "filename": "audio_extract.mp3",
      "container": "mp3",
      "video_codec": "none",
      "resolution": "none",
      "framerate": "none",
      "video_bitrate_kbps": 0,
      "audio_codec": "mp3",
      "audio_channels": 2,
      "audio_sample_rate": 44100,
      "audio_bitrate_kbps": 192,
      "notes": "Audio-only extraction for podcast companion feed."
    }
  },
  "deliverables_manifest": {
    "path": "/home/ga/Documents/deliverables_manifest.json",
    "required_fields": ["filename", "platform", "file_size_bytes", "duration_seconds", "video_codec", "audio_codec", "resolution"]
  }
}
SPECEOF

# Store ground truth for verifier
cat > /tmp/.distribution_ground_truth.json << 'GTEOF'
{
  "source_duration": 60,
  "platforms": {
    "broadcast": {
      "filename": "broadcast_delivery.mp4",
      "width": 1920, "height": 1080, "fps": 25,
      "video_codec": "h264", "audio_codec": "aac",
      "audio_channels": 2, "audio_sample_rate": 48000
    },
    "mobile": {
      "filename": "mobile_delivery.mp4",
      "width": 640, "height": 360, "fps": 30,
      "video_codec": "h264", "audio_codec": "aac",
      "audio_channels": 1, "audio_sample_rate": 44100
    },
    "web_streaming": {
      "filename": "web_delivery.mkv",
      "width": 1280, "height": 720, "fps": 30,
      "video_codec": "h264", "audio_codec": "aac",
      "audio_channels": 2, "audio_sample_rate": 44100
    },
    "audio_only": {
      "filename": "audio_extract.mp3",
      "audio_codec": "mp3", "audio_channels": 2,
      "audio_sample_rate": 44100, "is_audio_only": true
    }
  }
}
GTEOF

chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Launch VLC (no file loaded)
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
sleep 2

echo "Setup complete for multi_platform_distribution_transcode task"
