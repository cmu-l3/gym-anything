#!/bin/bash
# Export results for forensic_video_timeline_reconstruction task
set -e

source /workspace/scripts/task_utils.sh

echo "Exporting results for forensic_video_timeline_reconstruction..."

# Copy corrected timeline
cp -f /home/ga/Documents/corrected_timeline.json /tmp/forensic_corrected_timeline.json 2>/dev/null || true

# Copy evidence clips
mkdir -p /tmp/forensic_evidence_clips
for f in /home/ga/Videos/evidence_clips/*; do
    if [ -f "$f" ]; then
        cp -f "$f" "/tmp/forensic_evidence_clips/$(basename "$f")" 2>/dev/null || true
    fi
done

# Copy forensic snapshots from multiple possible locations
mkdir -p /tmp/forensic_snapshots
for dir in /home/ga/Pictures/forensic_snapshots /home/ga/Pictures/vlc /home/ga/Videos/evidence_clips; do
    for ext in png jpg jpeg PNG JPG; do
        for f in "$dir"/*."$ext"; do
            if [ -f "$f" ]; then
                cp -f "$f" "/tmp/forensic_snapshots/$(basename "$f")" 2>/dev/null || true
            fi
        done
    done
done

# Also check for snapshots directly in home directory or Desktop
for dir in /home/ga /home/ga/Desktop /home/ga/Documents; do
    for ext in png jpg jpeg PNG JPG; do
        for f in "$dir"/*."$ext"; do
            if [ -f "$f" ]; then
                cp -f "$f" "/tmp/forensic_snapshots/$(basename "$f")" 2>/dev/null || true
            fi
        done
    done
done

# Copy ground truth
cp -f /tmp/.forensic_ground_truth.json /tmp/forensic_ground_truth.json 2>/dev/null || true

# List what was exported
echo "Exported files:"
ls -la /tmp/forensic_corrected_timeline.json 2>/dev/null || echo "  No corrected timeline found"
echo "Evidence clips:"
ls -la /tmp/forensic_evidence_clips/ 2>/dev/null || echo "  No evidence clips found"
echo "Snapshots:"
ls -la /tmp/forensic_snapshots/ 2>/dev/null || echo "  No snapshots found"

# Kill VLC
kill_vlc

echo "Export complete for forensic_video_timeline_reconstruction"
