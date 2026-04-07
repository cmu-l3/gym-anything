#!/bin/bash
echo "=== Setting up Live Stage Cue Playback task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean slate for VLC
kill_vlc "ga"
rm -f /home/ga/.config/vlc/vlcrc
sudo -u ga mkdir -p /home/ga/.config/vlc

# Generate default vlcrc by launching and closing VLC briefly
su - ga -c "DISPLAY=:1 vlc --intf dummy vlc://quit"
sleep 2

# Create theater assets directory
ASSETS_DIR="/home/ga/Videos/theater_assets"
sudo -u ga mkdir -p "$ASSETS_DIR"

echo "Generating theater assets..."

# Cue 1: Video (Storm - complex fractal pattern)
sudo -u ga ffmpeg -y -f lavfi -i "mandelbrot=size=1280x720:rate=30" -t 5 \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
    "$ASSETS_DIR/cue_01_storm_projection.mp4" 2>/dev/null

# Cue 2: Audio (Thunder - explosive noise decay)
sudo -u ga ffmpeg -y -f lavfi -i "aevalsrc=random(0)*exp(-t):s=44100" -t 3 \
    -c:a flac \
    "$ASSETS_DIR/cue_02_thunder_clap.flac" 2>/dev/null

# Cue 3: Audio (Ariel Song - melodic sine sweep)
sudo -u ga ffmpeg -y -f lavfi -i "aevalsrc=sin(880*2*PI*t)*sin(440*2*PI*t):s=44100" -t 45 \
    -c:a libmp3lame -b:a 128k \
    "$ASSETS_DIR/cue_03_ariel_song.mp3" 2>/dev/null

# Cue 4: Video (Ambient - cellular automaton pattern)
sudo -u ga ffmpeg -y -f lavfi -i "cellauto=size=1280x720:rate=30:rule=110" -t 5 \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
    "$ASSETS_DIR/cue_04_island_ambient.mp4" 2>/dev/null

# Launch VLC so the agent can interact with it via GUI
su - ga -c "DISPLAY=:1 vlc &"
sleep 5

# Maximize the window for visibility
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="