#!/bin/bash
echo "=== Setting up create_photo_album_lecture task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create architecture photos directory
PHOTO_DIR="/home/ga/Documents/architecture_photos"
mkdir -p "$PHOTO_DIR"

# Download 8 real Wikimedia Commons images of Mesoamerican architecture
echo "Downloading reference images from Wikimedia Commons..."
URLs=(
    "https://upload.wikimedia.org/wikipedia/commons/thumb/5/51/Chichen_Itza_3.jpg/800px-Chichen_Itza_3.jpg"
    "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Tikal_Temple1_2006_08_11.JPG/800px-Tikal_Temple1_2006_08_11.JPG"
    "https://upload.wikimedia.org/wikipedia/commons/thumb/d/d4/Palenque_Ruins.jpg/800px-Palenque_Ruins.jpg"
    "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4b/Pir%C3%A1mide_del_Sol_Teotihuacan.jpg/800px-Pir%C3%A1mide_del_Sol_Teotihuacan.jpg"
    "https://upload.wikimedia.org/wikipedia/commons/thumb/7/77/Uxmal_Pir%C3%A1mide_del_Adivino.jpg/800px-Uxmal_Pir%C3%A1mide_del_Adivino.jpg"
    "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ad/Monte_Alb%C3%A1n_-_North_Platform.jpg/800px-Monte_Alb%C3%A1n_-_North_Platform.jpg"
    "https://upload.wikimedia.org/wikipedia/commons/thumb/c/cd/Tulum_-_El_Castillo.jpg/800px-Tulum_-_El_Castillo.jpg"
    "https://upload.wikimedia.org/wikipedia/commons/thumb/7/7b/Copan_Ruins.jpg/800px-Copan_Ruins.jpg"
)

i=1
for url in "${URLs[@]}"; do
    wget -q -O "${PHOTO_DIR}/photo_${i}.jpg" "$url" || echo "Failed to download $url"
    i=$((i+1))
done

chown -R ga:ga "$PHOTO_DIR"

# Ensure presentations directory exists
mkdir -p /home/ga/Documents/presentations
chown -R ga:ga /home/ga/Documents/presentations

# Remove any existing output file to ensure a clean state
rm -f /home/ga/Documents/presentations/architecture_lecture.pptx

# Kill any running WPS instance
kill_wps

# Launch WPS Presentation (without a specific file, to start a new document or home screen)
echo "Launching WPS Presentation..."
su - ga -c "DISPLAY=:1 wpp > /tmp/wpp_task.log 2>&1 &"

# Wait for WPS to fully load
echo "Waiting for WPS Presentation window..."
for i in {1..30}; do
    dismiss_eula_if_present
    # Check for WPS window
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "WPS Presentation\|Presentation1"; then
        echo "WPS Presentation window found"
        sleep 3
        break
    fi
    sleep 2
done

# Maximize the window
maximize_wps

# Take initial screenshot
sleep 1
take_screenshot /tmp/task_initial.png

echo "=== create_photo_album_lecture task setup complete ==="