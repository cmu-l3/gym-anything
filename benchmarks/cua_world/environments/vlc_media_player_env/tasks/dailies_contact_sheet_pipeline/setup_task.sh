#!/bin/bash
echo "=== Setting up Dailies Contact Sheet Pipeline Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Videos/dailies
mkdir -p /home/ga/Videos/dailies_output/frames
mkdir -p /home/ga/Videos/dailies_output/sheets
mkdir -p /home/ga/Documents

# Ensure VLC isn't running
pkill -f vlc || true

# Generate the 4 distinct dailies video files using ffmpeg
# We use testsrc2 as the base, apply a hue shift to make them distinct, and burn in text/timecode

echo "Generating scene12_take3.mp4 (Blue hue)..."
su - ga -c "ffmpeg -y -f lavfi -i 'testsrc2=size=1920x1080:rate=30:duration=60' \
  -vf \"hue=h=240,drawtext=text='SC12 TK3  %{pts\\:hms}':x=(w-tw)/2:y=h-150:fontsize=72:fontcolor=white:box=1:boxcolor=black@0.5\" \
  -c:v libx264 -preset ultrafast -crf 23 /home/ga/Videos/dailies/scene12_take3.mp4 2>/dev/null"

echo "Generating scene12_take4.mp4 (Green hue)..."
su - ga -c "ffmpeg -y -f lavfi -i 'testsrc2=size=1920x1080:rate=30:duration=60' \
  -vf \"hue=h=120,drawtext=text='SC12 TK4  %{pts\\:hms}':x=(w-tw)/2:y=h-150:fontsize=72:fontcolor=white:box=1:boxcolor=black@0.5\" \
  -c:v libx264 -preset ultrafast -crf 23 /home/ga/Videos/dailies/scene12_take4.mp4 2>/dev/null"

echo "Generating scene15_take1.mp4 (Orange/Warm hue)..."
su - ga -c "ffmpeg -y -f lavfi -i 'testsrc2=size=1920x1080:rate=30:duration=60' \
  -vf \"hue=h=30,drawtext=text='SC15 TK1  %{pts\\:hms}':x=(w-tw)/2:y=h-150:fontsize=72:fontcolor=white:box=1:boxcolor=black@0.5\" \
  -c:v libx264 -preset ultrafast -crf 23 /home/ga/Videos/dailies/scene15_take1.mp4 2>/dev/null"

echo "Generating scene18_take2.mp4 (Purple hue)..."
su - ga -c "ffmpeg -y -f lavfi -i 'testsrc2=size=1920x1080:rate=30:duration=60' \
  -vf \"hue=h=300,drawtext=text='SC18 TK2  %{pts\\:hms}':x=(w-tw)/2:y=h-150:fontsize=72:fontcolor=white:box=1:boxcolor=black@0.5\" \
  -c:v libx264 -preset ultrafast -crf 23 /home/ga/Videos/dailies/scene18_take2.mp4 2>/dev/null"

# Create the production brief
cat > /home/ga/Documents/contact_sheet_brief.txt << 'EOF'
=== PRODUCTION BRIEF: DAILIES CONTACT SHEETS ===
Date: Today
From: Post-Production Supervisor
To: Production Coordinator

We have 4 raw clips from today's shoot in ~/Videos/dailies/:
- scene12_take3.mp4
- scene12_take4.mp4
- scene15_take1.mp4
- scene18_take2.mp4

Before the edit session, please generate contact sheets and metadata for these clips.

REQUIREMENTS:
1. Extract frames: Every 10 seconds exactly (0s, 10s, 20s, 30s, 40s, 50s).
2. Save frames as PNGs to: ~/Videos/dailies_output/frames/<clip_name>/frame_NNs.png
3. Contact Sheets: Assemble the 6 frames per clip into a single 3x2 grid image (thumbnails 480x270). Save to: ~/Videos/dailies_output/sheets/<clip_name>_sheet.png
4. Metadata 1: Create ~/Videos/dailies_output/frame_index.json mapping each frame to its clip and timecode.
5. Metadata 2: Create ~/Videos/dailies_output/production_summary.json summarizing the clips processed (resolution, fps, duration) and total frames extracted.

Please ensure strict adherence to directory structures and filenames so our automated ingest scripts can pick them up.
EOF

# Set permissions
chown -R ga:ga /home/ga/Videos
chown ga:ga /home/ga/Documents/contact_sheet_brief.txt

# Start VLC in the background to simulate a ready environment
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
sleep 3

# Maximize VLC window if it exists
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="