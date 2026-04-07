#!/bin/bash
# Setup script for trade_show_video_wall_matrix task

echo "=== Setting up Trade Show Video Wall Matrix task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean up previous runs
rm -rf /home/ga/Videos/video_wall
rm -f /home/ga/Videos/tradeshow_master_4k.mp4
rm -f /home/ga/Documents/wall_manifest.json
rm -f /home/ga/Documents/wall_specs.txt

# Create necessary directories
mkdir -p /home/ga/Videos/video_wall
mkdir -p /home/ga/Documents

echo "Generating 4K master video (this may take a moment)..."
# Create a visually complex 4K (3840x2160) video with timecode and grid to ensure spatial crops are verifiable
# 30 seconds, 30 fps, H.264 with stereo audio
su - ga -c 'ffmpeg -y -f lavfi -i "testsrc2=size=3840x2160:rate=30:duration=30" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=30" \
  -vf "drawtext=text='\''TRADE SHOW MASTER 4K'\'':x=(w-tw)/2:y=(h-th)/2:fontsize=120:fontcolor=white:box=1:boxcolor=black@0.5,drawgrid=width=1920:height=1080:thickness=4:color=red@0.8" \
  -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p \
  -c:a aac -b:a 192k -ac 2 -ar 48000 \
  /home/ga/Videos/tradeshow_master_4k.mp4 2>/dev/null'

echo "Creating specification document..."
cat > /home/ga/Documents/wall_specs.txt << 'EOF'
=== 2x2 VIDEO WALL SPECIFICATION ===
Project: Tech Expo 2026 Booth Display
Master Source: tradeshow_master_4k.mp4 (3840x2160)
Layout: 2x2 Grid

Required Deliverables:
1. Four cropped MP4 files in /home/ga/Videos/video_wall/:
   - panel_TL.mp4 (Top-Left)
   - panel_TR.mp4 (Top-Right)
   - panel_BL.mp4 (Bottom-Left)
   - panel_BR.mp4 (Bottom-Right)
* All panels must be exactly 1920x1080 resolution.
* All audio MUST BE REMOVED from the panel files.

2. A JSON manifest file at /home/ga/Documents/wall_manifest.json EXACTLY following this structure:
{
  "master_video": "tradeshow_master_4k.mp4",
  "panels": {
    "TL": {"filename": "panel_TL.mp4", "resolution": "1920x1080", "offset_x": 0, "offset_y": 0},
    "TR": {"filename": "panel_TR.mp4", "resolution": "1920x1080", "offset_x": 1920, "offset_y": 0},
    "BL": {"filename": "panel_BL.mp4", "resolution": "1920x1080", "offset_x": 0, "offset_y": 1080},
    "BR": {"filename": "panel_BR.mp4", "resolution": "1920x1080", "offset_x": 1920, "offset_y": 1080}
  }
}
EOF

# Ensure correct ownership
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Pre-launch a terminal and VLC for the user
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/Videos &"
    sleep 2
fi

# Maximize the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take an initial screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="