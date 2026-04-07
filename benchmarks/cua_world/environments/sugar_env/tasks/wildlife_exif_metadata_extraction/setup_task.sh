#!/bin/bash
echo "=== Setting up wildlife_exif_metadata_extraction task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp
date +%s > /tmp/exif_task_start_ts
chmod 666 /tmp/exif_task_start_ts

# Install exiftool silently to deterministically prepare the dataset
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq libimage-exiftool-perl >/dev/null 2>&1

# Create target directory
PHOTO_DIR="/home/ga/Documents/wildlife_photos"
mkdir -p "$PHOTO_DIR"

# Download real wildlife images (with fallbacks to synthetic images if network is unreachable)
echo "Downloading wildlife dataset..."
wget -q -T 10 -O "$PHOTO_DIR/RedPanda.jpg" "https://upload.wikimedia.org/wikipedia/commons/b/b2/Ailurus_fulgens_RWP.jpg" || \
    convert -size 800x600 xc:darkred "$PHOTO_DIR/RedPanda.jpg"

wget -q -T 10 -O "$PHOTO_DIR/Monarch.jpg" "https://upload.wikimedia.org/wikipedia/commons/thumb/1/18/Monarch_Butterfly_Danaus_plexippus_Vertical_2000px.jpg/800px-Monarch_Butterfly_Danaus_plexippus_Vertical_2000px.jpg" || \
    convert -size 800x600 xc:orange "$PHOTO_DIR/Monarch.jpg"

wget -q -T 10 -O "$PHOTO_DIR/SeaTurtle.jpg" "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c2/Green_Sea_Turtle_grazing_seagrass.jpg/800px-Green_Sea_Turtle_grazing_seagrass.jpg" || \
    convert -size 800x600 xc:darkgreen "$PHOTO_DIR/SeaTurtle.jpg"

# Embed exact EXIF ground truth to ensure verification is strictly deterministic
echo "Embedding EXIF metadata..."
exiftool -overwrite_original -Model="Canon EOS 300D DIGITAL" -DateTimeOriginal="2010:04:15 14:30:00" "$PHOTO_DIR/RedPanda.jpg" >/dev/null
exiftool -overwrite_original -Model="Nikon D200" -DateTimeOriginal="2012:05:20 10:15:00" "$PHOTO_DIR/Monarch.jpg" >/dev/null
exiftool -overwrite_original -Model="Canon EOS 5D Mark II" -DateTimeOriginal="2018:08:05 09:45:00" "$PHOTO_DIR/SeaTurtle.jpg" >/dev/null

# Clean up possible backup files
rm -f "$PHOTO_DIR"/*_original 2>/dev/null

# Set correct ownership
chown -R ga:ga /home/ga/Documents/

# Clean up any previous attempts
rm -f /home/ga/Documents/extract_exif.sh /home/ga/Documents/extract_exif.py /home/ga/Documents/photo_metadata.csv

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Terminal activity for the agent
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch sugar-terminal-activity" &
sleep 5

# Take initial state screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/exif_task_initial.png" 2>/dev/null || true

echo "=== wildlife_exif_metadata_extraction task setup complete ==="