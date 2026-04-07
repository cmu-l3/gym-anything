#!/bin/bash
# Export results for atc_radio_communications_preprocessing task
set -e

echo "=== Exporting ATC Preprocessing Results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create export directory
mkdir -p /tmp/atc_export
chmod 777 /tmp/atc_export

# Copy requested deliverables
cp /home/ga/Music/processed/tower_clean.mp3 /tmp/atc_export/ 2>/dev/null || true
cp /home/ga/Music/processed/ground_clean.mp3 /tmp/atc_export/ 2>/dev/null || true
cp /home/ga/Pictures/diagnostics/tower_waveform.png /tmp/atc_export/ 2>/dev/null || true
cp /home/ga/Pictures/diagnostics/ground_waveform.png /tmp/atc_export/ 2>/dev/null || true
cp /home/ga/Music/processed/atc_review_playlist.xspf /tmp/atc_export/ 2>/dev/null || true
cp /home/ga/Documents/processing_report.json /tmp/atc_export/ 2>/dev/null || true

# Extract audio properties to JSON so verifier doesn't need to run ffprobe natively
for f in tower_clean.mp3 ground_clean.mp3; do
    if [ -f "/tmp/atc_export/$f" ]; then
        ffprobe -v error -show_format -show_streams -of json "/tmp/atc_export/$f" > "/tmp/atc_export/${f}_info.json" 2>/dev/null || true
    fi
done

echo "Exported files:"
ls -la /tmp/atc_export/

echo "=== Export complete ==="