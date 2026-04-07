#!/bin/bash
set -e
echo "=== Setting up rig_parenting_schematic_motion task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/OpenToonz/samples
mkdir -p /home/ga/OpenToonz/output
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/OpenToonz/projects

# Clear previous outputs to ensure fresh creation
rm -f /home/ga/OpenToonz/output/rigged_run.mp4
rm -f /home/ga/OpenToonz/projects/*.tnz

# 1. Generate the Nametag Asset (Real Data)
# Using ImageMagick to create a transparent PNG with text
echo "Generating asset..."
convert -size 200x100 xc:transparent -fill "#D10000" -stroke black -strokewidth 2 \
    -draw "roundrectangle 10,10 190,90 20,20" \
    -fill white -stroke none \
    -font DejaVu-Sans-Bold -pointsize 30 -gravity center -annotate 0 "PLAYER 1" \
    /home/ga/Desktop/nametag.png

chown ga:ga /home/ga/Desktop/nametag.png

# 2. Ensure Character Sample exists
# We check for the standard OpenToonz sample. If missing, we try to download or create a placeholder.
DWANKO_PATH="/home/ga/OpenToonz/samples/dwanko_run.pli" 
if [ ! -f "$DWANKO_PATH" ]; then
    echo "Downloading sample asset..."
    # Try official source
    wget -q --timeout=10 https://github.com/opentoonz/opentoonz_sample/raw/master/samples/dwanko/dwanko_run.pli -O "$DWANKO_PATH" || true
    
    # Fallback if download fails: Create a simple placeholder level
    if [ ! -s "$DWANKO_PATH" ]; then
        echo "Creating placeholder character..."
        convert -size 100x200 xc:transparent -fill blue -draw "circle 50,50 50,90" -draw "rectangle 20,90 80,180" "$DWANKO_PATH" 2>/dev/null || true
        mv "$DWANKO_PATH" "${DWANKO_PATH%.pli}.png" 2>/dev/null || true # Rename to png if using fallback
    fi
fi
chown -R ga:ga /home/ga/OpenToonz/samples

# 3. Launch OpenToonz
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss startup popups if any
for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="