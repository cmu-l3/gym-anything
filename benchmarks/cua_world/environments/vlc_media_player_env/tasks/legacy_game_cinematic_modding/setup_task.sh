#!/bin/bash
echo "=== Setting up Legacy Game Cinematic Modding Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Videos/mod_assets
mkdir -p /home/ga/Videos/mod_build
mkdir -p /home/ga/Documents

# Generate the master video (30 seconds, 1920x1080, H.264/AAC)
# The first 5 seconds have a distinct visual overlay representing the "MODERN STUDIO LOGO" that must be trimmed.
echo "Generating master video..."
su - ga -c "ffmpeg -y -f lavfi -i 'testsrc2=size=1920x1080:rate=30:duration=30' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=30' \
  -vf \"drawtext=text='MODERN STUDIO LOGO - TRIM THIS':enable='between(t,0,5)':x=(w-tw)/2:y=(h-th)/2:fontsize=96:fontcolor=white:box=1:boxcolor=red@0.8\" \
  -c:v libx264 -preset ultrafast -b:v 4M \
  -c:a aac -b:a 192k -ar 48000 \
  /home/ga/Videos/mod_assets/intro_master_1080p.mp4 2>/dev/null"

# Generate the engine specifications document
cat > /home/ga/Documents/engine_specs.txt << 'EOF'
COSMIC VANGUARD (2004) - CINEMATIC SPECIFICATIONS

The aging engine has a hardcoded video player. If the intro cinematic does not meet these EXACT specifications, the game will crash on startup.

Source File: /home/ga/Videos/mod_assets/intro_master_1080p.mp4
Output File: /home/ga/Videos/mod_build/intro_cinematic.avi

Requirements:
1. Container: AVI (.avi)
2. Video Codec: MPEG-4 (DivX/Xvid compatible)
3. Resolution: 800x600 EXACTLY. Ignore the 16:9 aspect ratio of the source; force it to 800x600 (it will look squished, this is expected).
4. Framerate: 30 fps
5. Audio: MP3, Stereo, 128 kbps, 44.1 kHz
6. Content Trim: The original master has a 5-second "MODERN STUDIO LOGO" at the beginning. You MUST trim this out. The new video should start at the 00:00:05 mark of the original.

Additional Deliverables:
- Loading Splash: /home/ga/Videos/mod_build/loading_splash.png
  (A snapshot of the VERY FIRST frame of your new trimmed cinematic, exactly 800x600 pixels)

- Mod Manifest: /home/ga/Videos/mod_build/mod_manifest.json
  (A JSON file containing exactly these keys: "filename", "container", "video_codec", "audio_codec", "resolution", "target_fps")
EOF

# Set permissions
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Launch VLC in the background to ensure application is available
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true

# Wait a moment for VLC to launch
sleep 3

# Maximize and focus VLC
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="