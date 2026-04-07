#!/bin/bash
set -e
echo "=== Exporting results for fitness_vod_normalization_pipeline ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

mkdir -p /tmp/normalized /tmp/deliverables
cp /home/ga/Videos/normalized/*.mp4 /tmp/normalized/ 2>/dev/null || true
cp /home/ga/Videos/deliverables/* /tmp/deliverables/ 2>/dev/null || true
cp /home/ga/Documents/class_metadata.json /tmp/class_metadata.json 2>/dev/null || true

echo "Export complete"