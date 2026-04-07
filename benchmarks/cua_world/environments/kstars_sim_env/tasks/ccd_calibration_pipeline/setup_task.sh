#!/bin/bash
set -e
echo "=== Setting up CCD Calibration Pipeline task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -rf /home/ga/Data
rm -f /home/ga/Documents/pipeline_spec.txt
rm -f /home/ga/reduce.py
rm -f /tmp/task_result.json
rm -f /tmp/data_export.tar.gz

# 3. Create necessary directories
mkdir -p /home/ga/Data/raw_lights
mkdir -p /home/ga/Data/raw_darks
mkdir -p /home/ga/Data/raw_flats
mkdir -p /home/ga/Data/calibrated
mkdir -p /home/ga/Documents

# 4. Start INDI and capture a dummy frame to determine EXACT simulator dimensions
# This ensures our pre-seeded darks/lights match the exact shape of the flats the agent will capture
ensure_indi_running
sleep 2
connect_all_devices
sleep 2

# Do a quick dummy capture to /tmp
indi_setprop "CCD Simulator.UPLOAD_MODE.UPLOAD_LOCAL=On" 2>/dev/null || true
indi_setprop "CCD Simulator.UPLOAD_SETTINGS.UPLOAD_DIR=/tmp" 2>/dev/null || true
indi_setprop "CCD Simulator.UPLOAD_SETTINGS.UPLOAD_PREFIX=sim_" 2>/dev/null || true
indi_setprop "CCD Simulator.CCD_EXPOSURE.CCD_EXPOSURE_VALUE=0.01" 2>/dev/null || true

# Wait up to 10 seconds for the dummy frame
for i in {1..10}; do
    if ls /tmp/sim_*.fits 1> /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# 5. Generate raw lights and darks using Python
# We read the dummy frame's shape so math operations (Raw - Dark) / Flat don't throw shape mismatches
python3 - << 'PYEOF'
import os
import glob
import numpy as np
from astropy.io import fits

shape = (1280, 1024)  # Default fallback
sim_files = glob.glob('/tmp/sim_*.fits')
if sim_files:
    try:
        shape = fits.getdata(sim_files[0]).shape
        print(f"Read simulator shape: {shape}")
    except:
        print(f"Failed to read shape, using default: {shape}")

np.random.seed(42)

# Generate 3 Darks
for i in range(1, 4):
    data = np.random.normal(500, 10, shape).astype(np.float32)
    hdu = fits.PrimaryHDU(data)
    hdu.header['IMAGETYP'] = 'DARK'
    hdu.header['EXPTIME'] = 60.0
    hdu.writeto(f'/home/ga/Data/raw_darks/dark_{i}.fits', overwrite=True)

# Generate 3 Lights
for i in range(1, 4):
    # Base sky background
    data = np.random.normal(2000, 50, shape).astype(np.float32)
    
    # Add a synthetic star in the center
    cx, cy = shape[0]//2, shape[1]//2
    y, x = np.ogrid[-cx:shape[0]-cx, -cy:shape[1]-cy]
    star = 10000 * np.exp(-(x**2 + y**2)/20.0)
    data += star.astype(np.float32)
    
    # Add dark current
    data += np.random.normal(500, 10, shape).astype(np.float32)

    hdu = fits.PrimaryHDU(data)
    hdu.header['IMAGETYP'] = 'LIGHT'
    hdu.header['FILTER'] = 'V'
    hdu.header['EXPTIME'] = 60.0
    hdu.writeto(f'/home/ga/Data/raw_lights/light_{i}.fits', overwrite=True)

print("Generated raw darks and lights.")
PYEOF

chown -R ga:ga /home/ga/Data

# 6. Reset CCD upload properties so the agent starts clean
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 7. Configure filter wheel slots
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
sleep 1

# 8. Create pipeline specification document
cat > /home/ga/Documents/pipeline_spec.txt << 'EOF'
CCD CALIBRATION PIPELINE SPECIFICATION
======================================
The observatory requires a custom Python pipeline to reduce tonight's data.

PHASE 1: HARDWARE ACQUISITION
-----------------------------
We are missing flat fields! Use KStars/INDI to capture them.
- Filter: V-band (Slot 2)
- Frame Type: FLAT
- Count: 5 frames
- Save to: /home/ga/Data/raw_flats/

PHASE 2: SOFTWARE PIPELINE
--------------------------
Write a Python script (e.g. ~/reduce.py) to calibrate the lights.
1. Darks: Median combine the 3 darks in /home/ga/Data/raw_darks/ into a `master_dark`.
2. Flats: Median combine your 5 flats in /home/ga/Data/raw_flats/ into a `master_flat`.
3. Normalize: `norm_flat = master_flat / np.mean(master_flat)`
4. Calibrate: For each light in /home/ga/Data/raw_lights/ (1 to 3):
      calibrated = (raw_light - master_dark) / norm_flat
5. Save: Output as float32 FITS to /home/ga/Data/calibrated/calibrated_1.fits, etc.

*Tip*: Use float32 for all numpy arrays to ensure mathematical precision matching the verifier.
EOF
chown ga:ga /home/ga/Documents/pipeline_spec.txt

# 9. Start and maximize KStars
ensure_kstars_running
sleep 3
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done
maximize_kstars
focus_kstars
sleep 1

take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="