#!/bin/bash
set -e
echo "=== Setting up Surface Roughness Profiling Task ==="

# 1. Create Directories
mkdir -p /home/ga/Fiji_Data/raw/surface
mkdir -p /home/ga/Fiji_Data/results/surface
chown -R ga:ga /home/ga/Fiji_Data

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# 3. Prepare Data (Real ImageJ Sample)
echo "Preparing sample image..."

# Use python to download and process the image to ensure consistent ground truth
python3 << 'PYEOF'
import urllib.request
import os
import json
import numpy as np
from PIL import Image

# URL for classic ImageJ sample "AuPbSn40" (Gold-Lead-Tin solder)
# It is a standard sample used for texture analysis
url = "https://imagej.net/images/AuPbSn40.jpg"
output_path = "/home/ga/Fiji_Data/raw/surface/surface_scan.tif"
gt_path = "/tmp/ground_truth_stats.json"

try:
    print(f"Downloading {url}...")
    urllib.request.urlretrieve(url, "/tmp/temp_sample.jpg")
    
    # Convert to 8-bit grayscale TIFF
    img = Image.open("/tmp/temp_sample.jpg").convert("L")
    img.save(output_path)
    print(f"Saved grayscale TIFF to {output_path}")
    
    # CALCULATE GROUND TRUTH STATISTICS
    # Treat pixel intensity (0-255) as height in nm
    arr = np.array(img, dtype=float)
    
    mean_val = np.mean(arr)
    std_val = np.std(arr) # Rq (RMS)
    min_val = np.min(arr)
    max_val = np.max(arr)
    median_val = np.median(arr)
    
    # Ra (Arithmetic Average) = mean(|x - mean|)
    ra_val = np.mean(np.abs(arr - mean_val))
    
    # Rz (Peak to Valley) = max - min
    rz_val = max_val - min_val
    
    gt_data = {
        "Ra": round(ra_val, 2),
        "Rq": round(std_val, 2),
        "Rz": round(rz_val, 2),
        "Mean_height": round(mean_val, 2),
        "Median_height": round(median_val, 2),
        "width": img.width,
        "height": img.height
    }
    
    with open(gt_path, "w") as f:
        json.dump(gt_data, f)
        
    print(f"Ground Truth Calculated: Ra={ra_val:.2f}, Rq={std_val:.2f}, Rz={rz_val:.2f}")

except Exception as e:
    print(f"Error preparing data: {e}")
    exit(1)
PYEOF

# 4. Create Calibration Info File
cat > /home/ga/Fiji_Data/raw/surface/calibration_info.txt << 'CALEOF'
Surface Profilometry Calibration Data
======================================
Instrument: Optical Profilometer
Sample: Au-Pb-Sn solder interconnect
Date: 2024-10-25

Spatial Calibration:
  Scale: 0.5 µm/pixel (X and Y)
  Method: Analyze > Set Scale
  Settings: Distance in pixels = 2, Known distance = 1, Unit = µm

Height Calibration:
  Pixel intensity maps directly to height.
  1 Intensity Unit = 1 nm
  Range: 0 - 255 nm
CALEOF

# Set permissions
chown -R ga:ga /home/ga/Fiji_Data
chmod 644 /home/ga/Fiji_Data/raw/surface/*

# 5. Launch Fiji
echo "Launching Fiji..."
if [ -f "/home/ga/launch_fiji.sh" ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" > /tmp/fiji.log 2>&1 &
else
    su - ga -c "DISPLAY=:1 fiji" > /tmp/fiji.log 2>&1 &
fi

# 6. Wait for Window and Maximize
echo "Waiting for Fiji window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ"; then
        echo "Fiji window found."
        sleep 2
        # Maximize
        DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 7. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "Setup complete."