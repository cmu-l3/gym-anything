#!/bin/bash
# Setup script for Roller Coaster Loop Reconstruction task
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_process() { local p=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do pgrep -f "$p" > /dev/null 2>&1 && return 0; sleep 1; e=$((e+1)); done; return 1; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Coaster Loop Reconstruction Task ==="

# 1. clean up previous run
kill_geogebra ga
sleep 1

# 2. Prepare directories
mkdir -p /home/ga/Documents/GeoGebra/projects
mkdir -p /home/ga/Documents/GeoGebra/assets
chown -R ga:ga /home/ga/Documents/GeoGebra

# 3. Download the asset (Roller Coaster Loop Image)
# Using a classic Schwarzkopf loop image (Revolution at Six Flags) or generic equivalent
IMAGE_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/2/29/Revolution_Loop_2.jpg/800px-Revolution_Loop_2.jpg"
IMAGE_DEST="/home/ga/Documents/GeoGebra/assets/coaster_loop.jpg"

if [ ! -f "$IMAGE_DEST" ]; then
    echo "Downloading reference image..."
    wget -q -O "$IMAGE_DEST" "$IMAGE_URL" || {
        echo "Failed to download image, creating placeholder..."
        # Fallback: create a dummy image with text if internet fails (unlikely in env, but safe)
        convert -size 800x600 xc:skyblue -pointsize 30 -draw "text 200,300 'Roller Coaster Loop'" "$IMAGE_DEST"
    }
    chown ga:ga "$IMAGE_DEST"
fi

# 4. Remove target file
rm -f /home/ga/Documents/GeoGebra/projects/coaster_reconstruction.ggb 2>/dev/null || true

# 5. Record start time
date +%s > /tmp/task_start_time

# 6. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_process "geogebra" 45; then
    echo "WARNING: GeoGebra process not found"
fi

if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window not found"
fi
sleep 5

# 7. Focus and Maximize
su - ga -c "DISPLAY=:1 xdotool mousemove 500 500 click 1" 2>/dev/null || true
focus_geogebra
sleep 1
maximize_geogebra
sleep 1

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Asset location: $IMAGE_DEST"
echo "Track Gauge: 1.2m"