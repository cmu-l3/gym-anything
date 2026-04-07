#!/bin/bash
set -e

echo "=== Setting up Indie Film Remediation Pipeline Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
SUBMISSION_DIR="/home/ga/Videos/festival_submission"
MASTERS_DIR="/home/ga/Videos/festival_masters"

mkdir -p "$SUBMISSION_DIR"
mkdir -p "$MASTERS_DIR"

# Ensure ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "ffmpeg could not be found, skipping setup..."
    exit 1
fi

# 1. Create the raw interlaced video (10 seconds, test pattern, with audio)
# Use +ilme+ildct to flag as interlaced.
echo "Generating raw_film.mp4..."
ffmpeg -y -f lavfi -i testsrc=d=10:s=1280x720:r=30 \
  -f lavfi -i sine=f=440:d=10 \
  -flags +ilme+ildct \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k \
  "$SUBMISSION_DIR/raw_film.mp4" 2>/dev/null

# 2. Create the English subtitle file (timing is 2 seconds early)
# Intended visual action happens at 00:00:03, but subtitles are at 00:00:01
echo "Generating english_subs.srt..."
cat > "$SUBMISSION_DIR/english_subs.srt" << 'SRTEOF'
1
00:00:01,000 --> 00:00:03,000
[Film Start] Welcome to the independent festival.

2
00:00:05,000 --> 00:00:07,000
This scene represents the duality of synchronization.
SRTEOF

# 3. Create the Director's Commentary audio (10 seconds, different tone)
echo "Generating directors_commentary.mp3..."
ffmpeg -y -f lavfi -i sine=f=880:d=10 \
  -c:a libmp3lame -b:a 128k \
  "$SUBMISSION_DIR/directors_commentary.mp3" 2>/dev/null

# 4. Create the Remediation Notes
echo "Generating remediation_notes.txt..."
cat > "$SUBMISSION_DIR/remediation_notes.txt" << 'NOTESEOF'
=== FESTIVAL SUBMISSION REMEDIATION NOTES ===
Film ID: CG26-042

Our initial QC pass found several critical issues with the raw_film.mp4 package. Please address all of them to produce the final exhibition masters.

1. AUDIO SYNC: The original audio in raw_film.mp4 trails the video by exactly 1.5 seconds (the sound plays 1500ms AFTER the visual event). It must be advanced/shifted to match the visual.
2. SUBTITLE SYNC: The text in english_subs.srt appears 2.0 seconds TOO EARLY (the text appears 2000ms BEFORE the dialogue). It must be delayed to match.
3. INTERLACING: The raw video has interlacing artifacts. Apply a deinterlacing filter to all outputs.

REQUIRED MASTERS (Save to /home/ga/Videos/festival_masters/):
A) exhibition_master.mkv -> MKV, deinterlaced, sync-corrected audio, sync-corrected soft-subtitles (embedded track).
B) hardsub_master.mp4 -> MP4, deinterlaced, sync-corrected audio, subtitles burned directly into the video frames (no sub tracks).
C) commentary_edition.mkv -> MKV, deinterlaced, sync-corrected audio (Track 1), and directors_commentary.mp3 (Track 2).

REPORT:
Create /home/ga/Videos/festival_masters/remediation_report.json matching this exact structure:
{
  "film_id": "CG26-042",
  "applied_audio_offset_ms": <integer representing offset applied>,
  "applied_subtitle_offset_ms": <integer representing offset applied>,
  "deinterlace_applied": true,
  "deliverables_generated": 3
}
NOTESEOF

# Fix permissions
chown -R ga:ga /home/ga/Videos

# Start VLC
if ! pgrep -f "vlc" > /dev/null; then
    su - ga -c "DISPLAY=:1 vlc --no-video-title-show &"
    sleep 3
fi

# Maximize VLC
DISPLAY=:1 wmctrl -r "VLC" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="