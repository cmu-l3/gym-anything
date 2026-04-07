#!/bin/bash
# Setup script for veterinary_ultrasound_diagnostic_export task

echo "=== Setting up Veterinary Ultrasound Diagnostic Export task ==="

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create necessary directories
RAW_DIR="/home/ga/Documents/Ultrasound_Raw"
mkdir -p "$RAW_DIR"
mkdir -p /home/ga/Documents/Cardiology_Referral
mkdir -p /tmp/gt_snapshots

# Generate visually distinct "uncompressed" legacy ultrasound files
# Using dynamic ffmpeg filters (mandelbrot, cellauto, testsrc2) so every frame is unique for exact timestamp verification
# Mixing in loud PCM noise to simulate raw machine audio that needs stripping
echo "Generating raw ultrasound simulation files (AVI with PCM audio)..."

# 1. Long Axis (15 seconds) - Mandelbrot zoom
ffmpeg -y -f lavfi -i "mandelbrot=size=800x600:rate=30" -f lavfi -i "anoisesrc=d=15:c=pink:r=44100" -t 15 \
    -c:v mpeg4 -b:v 15M -c:a pcm_s16le "$RAW_DIR/scan_long_axis.avi" 2>/dev/null

# 2. Short Axis (12 seconds) - Cellauto pattern
ffmpeg -y -f lavfi -i "cellauto=size=800x600:rate=30" -f lavfi -i "anoisesrc=d=12:c=brown:r=44100" -t 12 \
    -c:v mpeg4 -b:v 15M -c:a pcm_s16le "$RAW_DIR/scan_short_axis.avi" 2>/dev/null

# 3. Apical (10 seconds) - Testsrc2 with moving gradient
ffmpeg -y -f lavfi -i "testsrc2=size=800x600:rate=30" -f lavfi -i "anoisesrc=d=10:c=white:r=44100" -t 10 \
    -c:v mpeg4 -b:v 15M -c:a pcm_s16le "$RAW_DIR/scan_apical.avi" 2>/dev/null

# Generate Ground Truth Snapshots at the requested timestamps
echo "Extracting ground-truth diagnostic frames..."
ffmpeg -y -ss 00:00:05 -i "$RAW_DIR/scan_long_axis.avi" -vframes 1 /tmp/gt_snapshots/gt_long_axis.png 2>/dev/null
ffmpeg -y -ss 00:00:08 -i "$RAW_DIR/scan_short_axis.avi" -vframes 1 /tmp/gt_snapshots/gt_short_axis.png 2>/dev/null
ffmpeg -y -ss 00:00:04 -i "$RAW_DIR/scan_apical.avi" -vframes 1 /tmp/gt_snapshots/gt_apical.png 2>/dev/null

# Create the instructions file
cat > /home/ga/Documents/vet_notes.txt << 'EOF'
=== CARDIOLOGY REFERRAL NOTES ===
Patient: Bella
Species: Canine
Study: Echocardiogram

Instructions for Tech:
The cardiologist's portal only accepts small, web-friendly video files. 
Please transcode the 3 raw AVI files to MP4 (H.264 video).
IMPORTANT: Strip the audio entirely. The raw files contain loud, useless machine feedback.

Additionally, the specialist requested 3 still-frame snapshots (PNG format) captured at exact peak-systole moments:
- scan_long_axis: capture at 0:05
- scan_short_axis: capture at 0:08
- scan_apical: capture at 0:04

Create a JSON manifest named 'referral_manifest.json' with this exact structure:
{
  "patient_name": "Bella",
  "species": "Canine",
  "study_type": "Echocardiogram",
  "video_files": [
    "scan_long_axis.mp4",
    "scan_short_axis.mp4",
    "scan_apical.mp4"
  ],
  "snapshot_files": [
    "snapshot_long_axis.png",
    "snapshot_short_axis.png",
    "snapshot_apical.png"
  ]
}

Place all deliverables (3 MP4s, 3 PNGs, 1 JSON) in /home/ga/Documents/Cardiology_Referral/.
EOF

# Ensure correct ownership
chown -R ga:ga /home/ga/Documents

# Ensure VLC is running empty to provide a clean starting state
if ! pgrep -f "vlc" > /dev/null; then
    su - ga -c "DISPLAY=:1 vlc &"
    sleep 3
fi

# Maximize the VLC window
DISPLAY=:1 wmctrl -r "VLC" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot to prove task setup
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="