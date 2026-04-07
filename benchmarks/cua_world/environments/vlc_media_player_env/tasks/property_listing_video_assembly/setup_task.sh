#!/bin/bash
echo "=== Setting up property_listing_video_assembly task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

mkdir -p /home/ga/Pictures/property_tour
mkdir -p /home/ga/Music
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Videos/listing_output

# Determine system font for test generation
FONT="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
if [ ! -f "$FONT" ]; then
    FONT_OPT=""
else
    FONT_OPT="fontfile=$FONT:"
fi

# 1. Generate 8 distinct room photos
declare -a ROOMS=(
    "01|skyblue|Front Exterior"
    "02|wheat|Living Room"
    "03|darkseagreen|Kitchen"
    "04|bisque|Dining Room"
    "05|plum|Master Bedroom"
    "06|lightseagreen|Bathroom"
    "07|forestgreen|Backyard"
    "08|lightgray|Garage"
)

echo "Generating room images..."
for room in "${ROOMS[@]}"; do
    ID="${room%%|*}"
    REST="${room#*|}"
    COLOR="${REST%%|*}"
    TEXT="${REST#*|}"
    
    su - ga -c "ffmpeg -y -f lavfi -i 'color=c=${COLOR}:s=1920x1080:d=1' \
        -vf \"drawtext=${FONT_OPT}text='${TEXT}':fontsize=96:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=10:x=(w-tw)/2:y=(h-th)/2\" \
        -vframes 1 '/home/ga/Pictures/property_tour/room_${ID}.jpg' 2>/dev/null"
done

# 2. Generate Narration Audio (32 seconds)
echo "Generating narration audio..."
su - ga -c "ffmpeg -y -f lavfi -i 'sine=frequency=440:sample_rate=44100:duration=32' -c:a pcm_s16le -ar 44100 -ac 1 '/home/ga/Music/property_narration.wav' 2>/dev/null"

# 3. Create Production Spec
echo "Creating production spec..."
cat << 'EOF' > /home/ga/Documents/listing_video_spec.txt
=== PROPERTY LISTING VIDEO - PRODUCTION SPECIFICATION ===

INPUT ASSETS:
- Images: /home/ga/Pictures/property_tour/room_01.jpg through room_08.jpg
- Audio: /home/ga/Music/property_narration.wav (32 seconds)

ASSEMBLY INSTRUCTIONS:
1. Sequence the 8 room images in numerical order.
2. Each image must display for exactly 4 seconds (total duration 32 seconds).
3. Apply crossfade transitions between slides if possible (0.5s duration).
4. Apply a 1-second fade-from-black at the start and 1-second fade-to-black at the end.
5. Overlay the narration audio track so it plays for the entire video.

REQUIRED DELIVERABLES (Save to /home/ga/Videos/listing_output/):

1. Website Master: listing_master.mp4
   - Resolution: 1920x1080
   - Video Codec: H.264
   - Framerate: 30 fps
   - Audio: AAC

2. Mobile Version: listing_mobile.mp4
   - Resolution: 1280x720
   - Video Codec: H.264
   - Framerate: 30 fps
   - Audio: AAC

3. Instagram Square: listing_square.mp4
   - Resolution: 1080x1080 (Center crop or letterbox is acceptable)
   - Video Codec: H.264
   - Framerate: 30 fps
   - Audio: AAC

4. Email Attachment: listing_email.mp4
   - Resolution: 640x360
   - Video Codec: H.264
   - Framerate: 24 fps
   - Max File Size: < 8 MB
   - Audio: AAC

5. MLS Thumbnail: listing_thumbnail.jpg
   - Format: JPEG
   - Resolution: 400x300
   - Source: Extracted from room_01.jpg

6. Deliverables Manifest: manifest.json
   - Format: JSON object
   - Content: Must list all 5 media files generated (master, mobile, square, email, thumbnail).
   - Required fields per file: filename, width, height, duration_seconds, file_size_bytes, codec
EOF
chown ga:ga /home/ga/Documents/listing_video_spec.txt
chown -R ga:ga /home/ga/Pictures/property_tour
chown -R ga:ga /home/ga/Music
chown -R ga:ga /home/ga/Videos/listing_output

# Kill VLC and clear desktop UI states
pkill -f vlc || true
sleep 1
DISPLAY=:1 wmctrl -k on 2>/dev/null || true

# Take initial screenshot evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="