#!/bin/bash
echo "=== Setting up evidence_media_diagnostics task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Documents/evidence_intake
mkdir -p /home/ga/Documents/evidence_processed
mkdir -p /home/ga/Downloads

# Attempt to download a real CC0 video to use as authentic source material
BASE_VID="/tmp/real_video.mp4"
echo "Fetching authentic base media..."
if wget -q --timeout=15 -O "$BASE_VID" "https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_320x180.mp4"; then
    echo "Successfully downloaded real media."
else
    echo "Download failed. Falling back to generated test media."
    ffmpeg -y -f lavfi -i testsrc=size=640x360:rate=30:duration=60 -c:v libx264 -f lavfi -i sine=frequency=440:duration=60 -c:a aac "$BASE_VID" 2>/dev/null
fi

echo "Generating corrupted forensic evidence files..."

# Exhibit A: H.264/AAC in MP4 container, but wrongly named .avi
ffmpeg -y -i "$BASE_VID" -ss 0 -t 10 -c:v libx264 -preset ultrafast -c:a aac -f mp4 /home/ga/Documents/evidence_intake/exhibit_A.avi 2>/dev/null

# Exhibit B: MP4 container, H.264 video, but NO AUDIO (stripped)
ffmpeg -y -i "$BASE_VID" -ss 10 -t 10 -c:v libx264 -preset ultrafast -an -f mp4 /home/ga/Documents/evidence_intake/exhibit_B.mp4 2>/dev/null

# Exhibit C: MP3 Audio only, but wrongly named .wav
ffmpeg -y -i "$BASE_VID" -ss 20 -t 10 -vn -c:a libmp3lame -f mp3 /home/ga/Documents/evidence_intake/exhibit_C.wav 2>/dev/null

# Exhibit D: H.264/AAC in Matroska (MKV) container, but wrongly named .dat
ffmpeg -y -i "$BASE_VID" -ss 30 -t 10 -c:v libx264 -preset ultrafast -c:a aac -f matroska /home/ga/Documents/evidence_intake/exhibit_D.dat 2>/dev/null

# Exhibit E: VP8/Vorbis in WebM container, but wrongly named .flv
ffmpeg -y -i "$BASE_VID" -ss 40 -t 10 -c:v libvpx -preset ultrafast -c:a libvorbis -f webm /home/ga/Documents/evidence_intake/exhibit_E.flv 2>/dev/null

# Generate case brief document
cat > /home/ga/Documents/case_brief.txt << 'CASEEOF'
=== CYBERCRIME FORENSICS UNIT ===
CASE ID: 2026-VLC-FORENSICS
DATE: $(date)

SITUATION:
During a raid, an investigator recovered 5 media files from a partially wiped hard drive. 
The recovery software appended incorrect file extensions based on corrupted headers.

EXHIBITS (Location: /home/ga/Documents/evidence_intake/):
- exhibit_A.avi
- exhibit_B.mp4
- exhibit_C.wav
- exhibit_D.dat
- exhibit_E.flv

INSTRUCTIONS:
1. Inspect the files to find their true container formats and codecs.
2. Copy the files to /home/ga/Documents/evidence_processed/.
3. Rename them to have the EXACT correct extension for their actual container format.
4. Document your findings in /home/ga/Documents/evidence_report.json following standard procedure.
CASEEOF

# Fix permissions
chown -R ga:ga /home/ga/Documents

# Ensure VLC is not currently running
pkill -f vlc || true

# Start a terminal for the user to use for CLI diagnostics
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/Documents/evidence_intake &" 2>/dev/null || true
sleep 2

# Take initial screenshot for verification
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="