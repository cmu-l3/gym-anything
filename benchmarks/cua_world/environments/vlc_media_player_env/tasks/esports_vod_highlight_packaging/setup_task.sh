#!/bin/bash
echo "=== Setting up Esports VOD Highlight Packaging Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming check)
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Videos/esports_raw
mkdir -p /home/ga/Videos/social_highlights
mkdir -p /home/ga/Documents

# 1. Download real-world complex video (Sintel trailer/short as esports stand-in)
# It features highly dynamic audio and detailed 1080p visuals
echo "Downloading source video..."
SINTEL_URL="https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4"
wget -q --show-progress -O /tmp/sintel_full.mp4 "$SINTEL_URL" || true

# Check if download succeeded and is valid, otherwise use high-quality synthetic fallback
if [ -s /tmp/sintel_full.mp4 ]; then
    echo "Processing downloaded video to 5-minute raw recording..."
    # Trim to exactly 5 minutes for consistency
    ffmpeg -y -v error -i /tmp/sintel_full.mp4 -t 00:05:00 -c:v copy -c:a copy /home/ga/Videos/esports_raw/tournament_finals.mp4
else
    echo "Download failed. Generating realistic synthetic 5-minute video..."
    ffmpeg -y -v error -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=300" \
      -f lavfi -i "anoisesrc=c=pink:r=48000:a=0.1" \
      -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=300" \
      -filter_complex "[1:a][2:a]amix=inputs=2:duration=first:weights=1 0.5[aout]" \
      -map 0:v -map "[aout]" \
      -c:v libx264 -preset veryfast -b:v 4M \
      -c:a aac -b:a 192k \
      /home/ga/Videos/esports_raw/tournament_finals.mp4
fi

# 2. Generate Team Logo (Transparent PNG) using Python
echo "Generating team logo..."
cat << 'EOF' > /tmp/make_logo.py
from PIL import Image, ImageDraw, ImageFont
# Create 150x150 transparent background
img = Image.new('RGBA', (150, 150), (255, 255, 255, 0))
d = ImageDraw.Draw(img)
# Draw a red crest/shield
d.polygon([(75, 10), (140, 40), (140, 110), (75, 145), (10, 110), (10, 40)], fill=(220, 20, 60, 220))
d.text((45, 65), "TEAM\nLOGO", fill=(255, 255, 255, 255), align="center")
img.save('/home/ga/Videos/esports_raw/team_logo.png')
EOF
python3 /tmp/make_logo.py

# 3. Create Clipping Notes
cat > /home/ga/Videos/esports_raw/clipping_notes.txt << 'NOTES_EOF'
Tournament Highlights Extraction Notes
--------------------------------------
We need three highlight clips from the raw recording (tournament_finals.mp4) for our social media feeds.

For all clips, you MUST:
1. Burn 'team_logo.png' into the TOP-RIGHT corner of the video.
2. Normalize the audio (the commentators are way too loud compared to the game). Use a dynamic audio normalizer or volume compressor filter.
3. Export as MP4 using H.264 video and AAC audio.
4. Preserve original resolution (1920x1080).

Highlights to extract:
1. "The Ambush" -> Start: 0:52, End: 1:12
2. "Base Defense" -> Start: 2:05, End: 2:25
3. "Final Victory" -> Start: 3:40, End: 4:10

Save the outputs in /home/ga/Videos/social_highlights/ exactly as:
- highlight_1_ambush.mp4
- highlight_2_defense.mp4
- highlight_3_victory.mp4

Also create a manifest.json in the social_highlights folder listing:
{
  "highlights": [
     {"filename": "highlight_1_ambush.mp4", "duration_seconds": 20, "title": "The Ambush", "watermarked": true},
     ...
  ]
}
NOTES_EOF

# Ensure permissions
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Launch a terminal so the agent can start writing ffmpeg commands right away
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/Videos/esports_raw &"

# Wait and capture initial screenshot
sleep 3
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="