#!/bin/bash
echo "=== Setting up Social Media Content Repurposing Pipeline ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean up any existing state
pkill -f "vlc" 2>/dev/null || true
rm -rf /home/ga/Videos/social_package 2>/dev/null || true

# Create directories
mkdir -p /home/ga/Videos/social_package
mkdir -p /home/ga/Documents

# 1. Generate the 120-second Brand Campaign Video using FFmpeg
# Contains 6 distinct 20-second scenes with different colors and text
echo "Generating source video (this may take a moment)..."

FILTER="drawbox=x=0:y=0:w=1920:h=1080:color=blue@0.8:t=fill:enable='between(t,0,20)'"
FILTER="${FILTER},drawtext=text='Product Launch':fontsize=72:fontcolor=white:x=(w-tw)/2:y=(h-th)/2:enable='between(t,0,20)'"

FILTER="${FILTER},drawbox=x=0:y=0:w=1920:h=1080:color=green@0.8:t=fill:enable='between(t,20,40)'"
FILTER="${FILTER},drawtext=text='Customer Testimonial':fontsize=72:fontcolor=white:x=(w-tw)/2:y=(h-th)/2:enable='between(t,20,40)'"

FILTER="${FILTER},drawbox=x=0:y=0:w=1920:h=1080:color=orange@0.8:t=fill:enable='between(t,40,60)'"
FILTER="${FILTER},drawtext=text='Behind the Scenes':fontsize=72:fontcolor=white:x=(w-tw)/2:y=(h-th)/2:enable='between(t,40,60)'"

FILTER="${FILTER},drawbox=x=0:y=0:w=1920:h=1080:color=purple@0.8:t=fill:enable='between(t,60,80)'"
FILTER="${FILTER},drawtext=text='Team Interview':fontsize=72:fontcolor=white:x=(w-tw)/2:y=(h-th)/2:enable='between(t,60,80)'"

FILTER="${FILTER},drawbox=x=0:y=0:w=1920:h=1080:color=red@0.8:t=fill:enable='between(t,80,100)'"
FILTER="${FILTER},drawtext=text='Demo Walkthrough':fontsize=72:fontcolor=white:x=(w-tw)/2:y=(h-th)/2:enable='between(t,80,100)'"

FILTER="${FILTER},drawbox=x=0:y=0:w=1920:h=1080:color=teal@0.8:t=fill:enable='between(t,100,120)'"
FILTER="${FILTER},drawtext=text='Call to Action':fontsize=72:fontcolor=white:x=(w-tw)/2:y=(h-th)/2:enable='between(t,100,120)'"

# Add timecode overlay for agent orientation
FILTER="${FILTER},drawtext=text='TIMECODE %{pts\:hms}':fontsize=36:fontcolor=yellow:x=50:y=50:box=1:boxcolor=black@0.5"

su - ga -c "ffmpeg -y -f lavfi -i 'testsrc2=size=1920x1080:rate=30:duration=120' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=120' -vf \"${FILTER}\" -c:v libx264 -preset ultrafast -b:v 4M -c:a aac -b:a 128k -ac 2 /home/ga/Videos/brand_campaign.mp4 2>/dev/null"

# 2. Create the content brief document
cat > /home/ga/Documents/content_brief.txt << 'BRIEFEOF'
=== BRAND CAMPAIGN - SOCIAL MEDIA REPURPOSING BRIEF ===

Source: /home/ga/Videos/brand_campaign.mp4 (120s, 1920x1080, Landscape)
Output Directory: /home/ga/Videos/social_package/

We need you to process the master campaign video into a complete package of 15 deliverables.

DELIVERABLE 1: Landscape Highlights (1920x1080, H.264 MP4)
Extract these four 10-second clips using the exact timestamps:
- highlight_A.mp4 (0:05 to 0:15)
- highlight_B.mp4 (0:25 to 0:35)
- highlight_C.mp4 (1:05 to 1:15)
- highlight_D.mp4 (1:25 to 1:35)

DELIVERABLE 2: Vertical Crops for Reels (1080x1920, H.264 MP4)
Create a vertical center-cropped version (9:16 aspect ratio) for each of the highlights.
- vertical_A.mp4 (from highlight_A)
- vertical_B.mp4 (from highlight_B)
- vertical_C.mp4 (from highlight_C)
- vertical_D.mp4 (from highlight_D)

DELIVERABLE 3: Compilation Reel
Concatenate all 4 landscape highlights (A -> B -> C -> D) into one seamless video.
- compilation.mp4 (1920x1080, ~40 seconds)

DELIVERABLE 4: Audio-Only Podcast Teaser
Extract the stereo audio track from the compilation video.
- compilation_audio.mp3 (~40 seconds, MP3 format, NO video stream)

DELIVERABLE 5: Thumbnails
Capture one PNG image frame from the midpoint (5 seconds into the clip) of each landscape highlight.
- thumb_A.png (from highlight_A at t=5s)
- thumb_B.png
- thumb_C.png
- thumb_D.png

DELIVERABLE 6: JSON Manifest
Create a file named `manifest.json` structured as follows:
{
  "campaign": "Brand Campaign Q4",
  "source_file": "brand_campaign.mp4",
  "deliverables": {
    "highlights": ["highlight_A.mp4", "highlight_B.mp4", "highlight_C.mp4", "highlight_D.mp4"],
    "verticals": ["vertical_A.mp4", "vertical_B.mp4", "vertical_C.mp4", "vertical_D.mp4"],
    "compilation": "compilation.mp4",
    "audio": "compilation_audio.mp3",
    "thumbnails": ["thumb_A.png", "thumb_B.png", "thumb_C.png", "thumb_D.png"]
  }
}
BRIEFEOF

chown -R ga:ga /home/ga/Videos /home/ga/Documents

# 3. Open VLC and file manager for the agent
su - ga -c "DISPLAY=:1 vlc --no-video-title-show /home/ga/Videos/brand_campaign.mp4 &" 2>/dev/null || true
su - ga -c "DISPLAY=:1 pcmanfm /home/ga/Videos/social_package &" 2>/dev/null || true
sleep 3

# Maximize VLC
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="