#!/bin/bash
# Export results for podcast_episode_assembly_and_mastering task
set -e

source /workspace/scripts/task_utils.sh

echo "Exporting results for podcast_episode_assembly_and_mastering..."

# Copy podcast output files to /tmp/
mkdir -p /tmp/podcast_output
for f in /home/ga/Music/podcast_output/*; do
    if [ -f "$f" ]; then
        cp -f "$f" "/tmp/podcast_output/$(basename "$f")" 2>/dev/null || true
    fi
done

# Also check for files with common alternative naming patterns
for dir in /home/ga/Music /home/ga/Music/podcast_output /home/ga/Documents; do
    for ext in wav mp3 WAV MP3; do
        for f in "$dir"/*episode*."$ext" "$dir"/*master*."$ext" "$dir"/*highlight*."$ext" "$dir"/*dist*."$ext"; do
            if [ -f "$f" ]; then
                cp -f "$f" "/tmp/podcast_output/$(basename "$f")" 2>/dev/null || true
            fi
        done
    done
done

# Copy ground truth
cp -f /tmp/.podcast_ground_truth.json /tmp/podcast_ground_truth.json 2>/dev/null || true

# List what was exported
echo "Exported files:"
ls -la /tmp/podcast_output/ 2>/dev/null || echo "  No podcast output files found"

# Kill VLC
kill_vlc

echo "Export complete for podcast_episode_assembly_and_mastering"
