#!/bin/bash
# Setup script for gallery_video_installation_prep task
set -e

echo "=== Setting up gallery_video_installation_prep task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Try to source utils, fallback if missing
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Kill any existing VLC instances
pkill -f "vlc" 2>/dev/null || true

# Create required directories
mkdir -p /home/ga/Videos/source_artworks
mkdir -p /home/ga/Videos/gallery_ready
mkdir -p /home/ga/Documents

# Generate source artworks with ffmpeg (abstract patterns and tones)
# alpha: 1920x1080, audio
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=30" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=30" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k \
  /home/ga/Videos/source_artworks/artwork_alpha.mp4 2>/dev/null

# beta: 1920x1080, audio
ffmpeg -y -f lavfi -i "color=c=blue:size=1920x1080:rate=30:duration=25" \
  -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=25" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k \
  /home/ga/Videos/source_artworks/artwork_beta.mp4 2>/dev/null

# gamma: 1920x1080, audio
ffmpeg -y -f lavfi -i "testsrc=size=1920x1080:rate=30:duration=20" \
  -f lavfi -i "sine=frequency=220:sample_rate=48000:duration=20" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k \
  /home/ga/Videos/source_artworks/artwork_gamma.mp4 2>/dev/null

# delta: 1280x720, audio
ffmpeg -y -f lavfi -i "smptebars=size=1280x720:rate=30:duration=15" \
  -f lavfi -i "sine=frequency=660:sample_rate=48000:duration=15" \
  -c:v libx264 -preset ultrafast -b:v 1M \
  -c:a aac -b:a 128k \
  /home/ga/Videos/source_artworks/artwork_delta.mp4 2>/dev/null

# Create room specifications document
cat > /home/ga/Documents/room_specs.txt << 'SPECEOF'
=== EXHIBITION INSTALLATION REQUIREMENTS ===
Exhibition: "Digital Horizons"
Date: October 14, 2026
Source Files Location: /home/ga/Videos/source_artworks/
Output Files Location: /home/ga/Videos/gallery_ready/

Target Video Codec for all rooms: H.264 (AVC)
Target Container for all rooms: MP4

--- ROOM A ---
Display Name: Main Hall
Source File: artwork_alpha.mp4
Output Filename: room_a_main_hall.mp4
Orientation: Landscape
Resolution: 1920x1080
Audio: YES (Keep original audio)

--- ROOM B ---
Display Name: Quiet Gallery
Source File: artwork_beta.mp4
Output Filename: room_b_quiet_gallery.mp4
Orientation: Landscape
Resolution: 1280x720
Audio: NO (Must be completely stripped/removed, not just muted)

--- ROOM C ---
Display Name: Tower Alcove
Source File: artwork_gamma.mp4
Output Filename: room_c_tower_alcove.mp4
Orientation: Portrait (Must be rotated 90 degrees)
Resolution: 1080x1920 (Width MUST be 1080, Height MUST be 1920)
Audio: YES (Keep original audio)

--- ROOM D ---
Display Name: Lobby Screen
Source File: artwork_delta.mp4
Output Filename: room_d_lobby_screen.mp4
Orientation: Landscape
Resolution: 640x480
Audio: NO (Must be completely stripped/removed)

--- DELIVERABLES ---
1. All 4 transcoded files saved to the gallery_ready folder.
2. An M3U playlist file at /home/ga/Videos/gallery_ready/installation_test.m3u containing the 4 output files in room order (A, B, C, D).
3. A JSON manifest file at /home/ga/Documents/installation_manifest.json documenting the final room configurations.
   (Required fields per room: room identifier, output filename, resolution, audio status, orientation).
SPECEOF

# Fix permissions
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

# Start VLC in the background for the user
su - ga -c "DISPLAY=:1 vlc --no-video-title-show > /dev/null 2>&1 &"
sleep 3

echo "=== Task setup complete ==="