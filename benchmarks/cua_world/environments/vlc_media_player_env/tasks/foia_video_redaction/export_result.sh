#!/bin/bash
# Export results for foia_video_redaction task
set -e

echo "=== Exporting FOIA Video Redaction Results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare output directory in /tmp for reliable copying
mkdir -p /tmp/foia_output
rm -rf /tmp/foia_output/*

# Copy expected output files safely
for f in /home/ga/Videos/foia_release/*; do
    if [ -f "$f" ]; then
        cp -f "$f" "/tmp/foia_output/$(basename "$f")" 2>/dev/null || true
    fi
done

# Also check documents and videos root directories just in case the agent saved them there
for dir in /home/ga/Videos /home/ga/Documents; do
    for f in "$dir"/evidence_*.mp4 "$dir"/*.json; do
        if [ -f "$f" ]; then
            # Avoid overwriting if they are already in the correct folder
            if [ ! -f "/tmp/foia_output/$(basename "$f")" ]; then
                cp -f "$f" "/tmp/foia_output/$(basename "$f")" 2>/dev/null || true
            fi
        fi
    done
done

# Copy ground truth
cp -f /tmp/.foia_ground_truth.json /tmp/foia_output/ground_truth.json 2>/dev/null || true

# List what was exported
echo "Exported files in /tmp/foia_output/:"
ls -la /tmp/foia_output/ 2>/dev/null

# Clean up VLC
pkill -f "vlc" 2>/dev/null || true

echo "=== Export Complete ==="