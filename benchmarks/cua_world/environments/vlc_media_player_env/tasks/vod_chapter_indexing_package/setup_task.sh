#!/bin/bash
echo "=== Setting up VOD Chapter Indexing Package Task ==="

# Terminate existing VLC instances
pkill -f "vlc" 2>/dev/null || true

# Setup required directories
mkdir -p /home/ga/Videos/vod_package
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Videos /home/ga/Documents

echo "Generating synthetic documentary footage with visual chapter markers..."

# Create a 90-second video with 6 distinct sections (15 seconds each)
# Each section has a different background color and a title
FILTER="drawbox=x=0:y=0:w=1920:h=1080:color=0x00008B@1:t=fill:enable='between(t,0,15)'"
FILTER="${FILTER},drawbox=x=0:y=0:w=1920:h=1080:color=0x006400@1:t=fill:enable='between(t,15,30)'"
FILTER="${FILTER},drawbox=x=0:y=0:w=1920:h=1080:color=0x8B0000@1:t=fill:enable='between(t,30,45)'"
FILTER="${FILTER},drawbox=x=0:y=0:w=1920:h=1080:color=0x800080@1:t=fill:enable='between(t,45,60)'"
FILTER="${FILTER},drawbox=x=0:y=0:w=1920:h=1080:color=0x008080@1:t=fill:enable='between(t,60,75)'"
FILTER="${FILTER},drawbox=x=0:y=0:w=1920:h=1080:color=0xFFA500@1:t=fill:enable='between(t,75,90)'"

# Add titles for each segment
FILTER="${FILTER},drawtext=text='Origins of Computing':x=(w-tw)/2:y=(h-th)/2:fontsize=64:fontcolor=white:enable='between(t,0,15)'"
FILTER="${FILTER},drawtext=text='The Mainframe Era':x=(w-tw)/2:y=(h-th)/2:fontsize=64:fontcolor=white:enable='between(t,15,30)'"
FILTER="${FILTER},drawtext=text='Personal Computing Revolution':x=(w-tw)/2:y=(h-th)/2:fontsize=64:fontcolor=white:enable='between(t,30,45)'"
FILTER="${FILTER},drawtext=text='The Internet Age':x=(w-tw)/2:y=(h-th)/2:fontsize=64:fontcolor=white:enable='between(t,45,60)'"
FILTER="${FILTER},drawtext=text='Mobile Computing':x=(w-tw)/2:y=(h-th)/2:fontsize=64:fontcolor=white:enable='between(t,60,75)'"
FILTER="${FILTER},drawtext=text='Artificial Intelligence':x=(w-tw)/2:y=(h-th)/2:fontsize=64:fontcolor=white:enable='between(t,75,90)'"

# Execute FFmpeg creation (silent mode)
ffmpeg -y \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=90" \
  -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=90" \
  -vf "${FILTER}" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k \
  /home/ga/Videos/documentary_computing.mp4 >/dev/null 2>&1

echo "Creating chapter reference sheet..."

cat > /home/ga/Documents/chapter_sheet.txt << 'EOF'
=== DOCUMENTARY CHAPTER METADATA ===

Chapter 1
Title: Origins of Computing
Start: 0:00
End: 0:15
Description: Early mechanical calculators and the birth of computational theory.
Visual Cue: Dark blue background

Chapter 2
Title: The Mainframe Era
Start: 0:15
End: 0:30
Description: Room-sized computers that powered early business and government.
Visual Cue: Dark green background

Chapter 3
Title: Personal Computing Revolution
Start: 0:30
End: 0:45
Description: The transition of computers from enterprise to the home.
Visual Cue: Dark red background

Chapter 4
Title: The Internet Age
Start: 0:45
End: 1:00
Description: Global connectivity and the explosion of the World Wide Web.
Visual Cue: Purple background

Chapter 5
Title: Mobile Computing
Start: 1:00
End: 1:15
Description: Smartphones and putting a computer in every pocket.
Visual Cue: Teal background

Chapter 6
Title: Artificial Intelligence
Start: 1:15
End: 1:30
Description: Machine learning and the future of intelligent systems.
Visual Cue: Orange background
EOF

# Make sure permissions are correct for the ga user
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Launch VLC with no file loaded so the user can begin
echo "Launching VLC media player..."
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
sleep 3

# Maximize VLC window
DISPLAY=:1 wmctrl -r "VLC" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Capture initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="