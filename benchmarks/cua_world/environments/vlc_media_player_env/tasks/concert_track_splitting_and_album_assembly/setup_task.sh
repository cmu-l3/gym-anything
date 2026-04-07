#!/bin/bash
set -e
echo "=== Setting up Concert Track Splitting Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Music/album_output/tracks
mkdir -p /home/ga/Music/album_output/thumbnails
mkdir -p /home/ga/Music/album_output/previews
mkdir -p /tmp/concert_parts

# 1. Generate the concert video
# Using testsrc2 (moving pattern) with text overlays to represent real data/different acts
echo "Generating concert segments..."

# Act 1: 0:00 - 0:20 (20s)
ffmpeg -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=20" -f lavfi -i "sine=frequency=261.63:sample_rate=44100:duration=20" \
    -vf "hue=h=180:s=1,drawtext=text='Act 1 - Marina Cortez':x=(w-tw)/2:y=h/2:fontsize=64:fontcolor=white:box=1:boxcolor=black@0.6" \
    -c:v libx264 -preset ultrafast -b:v 2M -c:a aac -b:a 128k -pix_fmt yuv420p /tmp/concert_parts/part1.mp4 -y -loglevel error

# Gap 1: 0:20 - 0:22 (2s)
ffmpeg -f lavfi -i "color=c=black:size=1280x720:rate=30:duration=2" -f lavfi -i "anullsrc=sample_rate=44100:channel_layout=mono:duration=2" \
    -c:v libx264 -preset ultrafast -b:v 1M -c:a aac -b:a 128k -pix_fmt yuv420p /tmp/concert_parts/gap1.mp4 -y -loglevel error

# Act 2: 0:22 - 0:44 (22s)
ffmpeg -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=22" -f lavfi -i "sine=frequency=329.63:sample_rate=44100:duration=22" \
    -vf "hue=h=120:s=1,drawtext=text='Act 2 - The Parallax':x=(w-tw)/2:y=h/2:fontsize=64:fontcolor=white:box=1:boxcolor=black@0.6" \
    -c:v libx264 -preset ultrafast -b:v 2M -c:a aac -b:a 128k -pix_fmt yuv420p /tmp/concert_parts/part2.mp4 -y -loglevel error

# Gap 2: 0:44 - 0:46 (2s)
ffmpeg -f lavfi -i "color=c=black:size=1280x720:rate=30:duration=2" -f lavfi -i "anullsrc=sample_rate=44100:channel_layout=mono:duration=2" \
    -c:v libx264 -preset ultrafast -b:v 1M -c:a aac -b:a 128k -pix_fmt yuv420p /tmp/concert_parts/gap2.mp4 -y -loglevel error

# Act 3: 0:46 - 1:08 (22s)
ffmpeg -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=22" -f lavfi -i "sine=frequency=392.00:sample_rate=44100:duration=22" \
    -vf "hue=h=300:s=1,drawtext=text='Act 3 - Aisha Ren':x=(w-tw)/2:y=h/2:fontsize=64:fontcolor=white:box=1:boxcolor=black@0.6" \
    -c:v libx264 -preset ultrafast -b:v 2M -c:a aac -b:a 128k -pix_fmt yuv420p /tmp/concert_parts/part3.mp4 -y -loglevel error

# Gap 3: 1:08 - 1:10 (2s)
ffmpeg -f lavfi -i "color=c=black:size=1280x720:rate=30:duration=2" -f lavfi -i "anullsrc=sample_rate=44100:channel_layout=mono:duration=2" \
    -c:v libx264 -preset ultrafast -b:v 1M -c:a aac -b:a 128k -pix_fmt yuv420p /tmp/concert_parts/gap3.mp4 -y -loglevel error

# Act 4: 1:10 - 1:32 (22s)
ffmpeg -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=22" -f lavfi -i "sine=frequency=440.00:sample_rate=44100:duration=22" \
    -vf "hue=h=45:s=1,drawtext=text='Act 4 - Codec Nine':x=(w-tw)/2:y=h/2:fontsize=64:fontcolor=white:box=1:boxcolor=black@0.6" \
    -c:v libx264 -preset ultrafast -b:v 2M -c:a aac -b:a 128k -pix_fmt yuv420p /tmp/concert_parts/part4.mp4 -y -loglevel error

# Gap 4: 1:32 - 1:34 (2s)
ffmpeg -f lavfi -i "color=c=black:size=1280x720:rate=30:duration=2" -f lavfi -i "anullsrc=sample_rate=44100:channel_layout=mono:duration=2" \
    -c:v libx264 -preset ultrafast -b:v 1M -c:a aac -b:a 128k -pix_fmt yuv420p /tmp/concert_parts/gap4.mp4 -y -loglevel error

# Act 5: 1:34 - 1:56 (22s)
ffmpeg -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=22" -f lavfi -i "sine=frequency=523.25:sample_rate=44100:duration=22" \
    -vf "hue=h=0:s=0,drawtext=text='Act 5 - Elena Voss':x=(w-tw)/2:y=h/2:fontsize=64:fontcolor=black:box=1:boxcolor=white@0.6" \
    -c:v libx264 -preset ultrafast -b:v 2M -c:a aac -b:a 128k -pix_fmt yuv420p /tmp/concert_parts/part5.mp4 -y -loglevel error

# Concatenate all parts
echo "Concatenating parts..."
cat > /tmp/concert_parts/concat.txt << 'EOF'
file 'part1.mp4'
file 'gap1.mp4'
file 'part2.mp4'
file 'gap2.mp4'
file 'part3.mp4'
file 'gap3.mp4'
file 'part4.mp4'
file 'gap4.mp4'
file 'part5.mp4'
EOF

ffmpeg -f concat -safe 0 -i /tmp/concert_parts/concat.txt -c copy /home/ga/Videos/venue_showcase_2024.mp4 -y -loglevel error
rm -rf /tmp/concert_parts

# 2. Generate the Setlist Document
cat > /home/ga/Documents/showcase_setlist.txt << 'EOF'
VENUE SHOWCASE 2024 - SETLIST

Track 1: 0:00 - 0:20 | Title: Opening Waves | Artist: Marina Cortez
Track 2: 0:22 - 0:44 | Title: Neon Drift | Artist: The Parallax
Track 3: 0:46 - 1:08 | Title: Quiet Thunder | Artist: Aisha Ren
Track 4: 1:10 - 1:32 | Title: Binary Sunset | Artist: Codec Nine
Track 5: 1:34 - 1:56 | Title: Last Light | Artist: Elena Voss

Deliverables Required:
- Audio-only MP3s with ID3 tags (Title, Artist, Album="Venue Showcase 2024", Track Number).
- Representative thumbnail (PNG) per track.
- 8-second preview clip (MP4) per track.
- A JSON manifest 'album_manifest.json' cataloging the exports.
EOF

# Set permissions
chown -R ga:ga /home/ga/Videos /home/ga/Documents /home/ga/Music

# Open VLC maximized (empty)
su - ga -c "DISPLAY=:1 vlc &" 2>/dev/null || true
sleep 3
DISPLAY=:1 wmctrl -r "VLC" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="