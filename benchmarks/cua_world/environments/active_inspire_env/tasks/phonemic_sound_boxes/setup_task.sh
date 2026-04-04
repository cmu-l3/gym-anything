#!/bin/bash
echo "=== Setting up Phonemic Sound Boxes Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Prepare Directories
mkdir -p /home/ga/Documents/Flipcharts
mkdir -p /home/ga/Pictures/ActivInspire
chown -R ga:ga /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Pictures/ActivInspire

# 2. Clean previous outputs
rm -f /home/ga/Documents/Flipcharts/phonemic_awareness.flipchart 2>/dev/null || true
rm -f /home/ga/Documents/Flipcharts/phonemic_awareness.flp 2>/dev/null || true

# 3. Download/Generate Real Assets
# We need reliable images for the task. We try to download real ones, 
# but fallback to generated labeled images to ensure the task is runnable 
# even without internet or if URLs break.

echo "Preparing image assets..."

# Cat Image (3 sounds)
if ! wget -q -O /home/ga/Pictures/ActivInspire/cat.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Cat03.jpg/320px-Cat03.jpg"; then
    echo "Download failed, generating placeholder for cat.jpg"
    convert -size 320x240 xc:lightgray -font DejaVu-Sans -pointsize 40 -gravity center -draw "text 0,0 'CAT'" /home/ga/Pictures/ActivInspire/cat.jpg
fi

# Frog Image (4 sounds)
if ! wget -q -O /home/ga/Pictures/ActivInspire/frog.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/1/18/Rana_catesbeiana_02.jpg/320px-Rana_catesbeiana_02.jpg"; then
    echo "Download failed, generating placeholder for frog.jpg"
    convert -size 320x240 xc:lightgreen -font DejaVu-Sans -pointsize 40 -gravity center -draw "text 0,0 'FROG'" /home/ga/Pictures/ActivInspire/frog.jpg
fi

chown ga:ga /home/ga/Pictures/ActivInspire/*.jpg

# 4. Record Initial State
date +%s > /tmp/task_start_time
list_flipcharts "/home/ga/Documents/Flipcharts" | wc -l > /tmp/initial_file_count

# 5. Launch Application
ensure_activinspire_running
focus_activinspire

# 6. Initial Evidence
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Assets prepared in /home/ga/Pictures/ActivInspire/"