#!/bin/bash
# Export results for educational_video_accessibility_compliance task
set -e

source /workspace/scripts/task_utils.sh

echo "Exporting results for educational_video_accessibility_compliance..."

# Copy all accessible output files to /tmp/
mkdir -p /tmp/accessible_output
for f in /home/ga/Videos/accessible_output/*; do
    if [ -f "$f" ]; then
        cp -f "$f" "/tmp/accessible_output/$(basename "$f")" 2>/dev/null || true
    fi
done

# Also check alternative locations for SRT files
for dir in /home/ga/Videos /home/ga/Documents /home/ga/Videos/subtitles; do
    for f in "$dir"/*.srt "$dir"/*.SRT; do
        if [ -f "$f" ]; then
            cp -f "$f" "/tmp/accessible_output/$(basename "$f")" 2>/dev/null || true
        fi
    done
done

# Check for snapshot/thumbnail files in common locations
for dir in /home/ga/Pictures/vlc /home/ga/Pictures /home/ga/Videos/accessible_output; do
    for f in "$dir"/section_*.png "$dir"/section_*.jpg; do
        if [ -f "$f" ]; then
            cp -f "$f" "/tmp/accessible_output/$(basename "$f")" 2>/dev/null || true
        fi
    done
done

# Copy ground truth
cp -f /tmp/.accessibility_ground_truth.json /tmp/accessibility_ground_truth.json 2>/dev/null || true

# List what was exported
echo "Exported files:"
ls -la /tmp/accessible_output/ 2>/dev/null || echo "  No accessible output files found"

# Kill VLC
kill_vlc

echo "Export complete for educational_video_accessibility_compliance"
