#!/bin/bash
set -e
echo "=== Setting up SEM Feature Measurement Task ==="

# 1. Create directories
mkdir -p /home/ga/Fiji_Data/raw/sem
mkdir -p /home/ga/Fiji_Data/results/sem
chown -R ga:ga /home/ga/Fiji_Data

# 2. Clean previous results
rm -f /home/ga/Fiji_Data/results/sem/annotated_sem.png
rm -f /home/ga/Fiji_Data/results/sem/grain_measurements.csv
rm -f /home/ga/Fiji_Data/results/sem/measurement_summary.txt

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Download and prepare the image
# We use the standard AuPbSn40 image from NIH ImageJ samples
SEM_IMG="/home/ga/Fiji_Data/raw/sem/AuPbSn40.tif"
if [ ! -f "$SEM_IMG" ]; then
    echo "Downloading AuPbSn40 SEM image..."
    wget -q --timeout=30 "https://imagej.nih.gov/ij/images/AuPbSn40.jpg" -O /tmp/AuPbSn40.jpg || \
    wget -q --timeout=30 "https://wsr.imagej.net/images/AuPbSn40.jpg" -O /tmp/AuPbSn40.jpg

    # Convert to TIFF using Python (Pillow) to ensure consistent metadata handling in Fiji
    python3 -c "from PIL import Image; Image.open('/tmp/AuPbSn40.jpg').save('$SEM_IMG')"
    rm -f /tmp/AuPbSn40.jpg
    chown ga:ga "$SEM_IMG"
fi

# 5. Create a "Logbook" file with calibration info (context for the agent)
cat > /home/ga/Fiji_Data/raw/sem/microscope_log.txt << 'EOF'
=== MICROSCOPE SESSION LOG ===
Date: 2023-10-15
Operator: Lab Tech 04
Sample: Au-Pb-Sn Solder Alloy
Instrument: FEI Quanta 200
--------------------------------
Image ID: AuPbSn40
Mag: 600x
Accelerating Voltage: 20kV
Detector: BSE (Backscattered Electron)
Image Width: 800 pixels
Horizontal Field Width (HFW): 256 µm
--------------------------------
EOF
chown ga:ga /home/ga/Fiji_Data/raw/sem/microscope_log.txt

# 6. Launch Fiji with the image loaded
echo "Launching Fiji..."
pkill -f "fiji" || true
pkill -f "ImageJ" || true

# Use the environment's launch script if available, else direct
if [ -x "/home/ga/launch_fiji.sh" ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh '$SEM_IMG' &"
else
    su - ga -c "DISPLAY=:1 /usr/local/bin/fiji '$SEM_IMG' &"
fi

# 7. Wait for window and maximize
echo "Waiting for Fiji..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "AuPbSn40"; then
        echo "Image window detected."
        sleep 2
        # Maximize the specific image window
        DISPLAY=:1 wmctrl -r "AuPbSn40" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="