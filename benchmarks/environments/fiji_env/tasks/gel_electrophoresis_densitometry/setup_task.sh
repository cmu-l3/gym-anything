#!/bin/bash
echo "=== Setting up Gel Electrophoresis Densitometry task ==="

# Record task start timestamp (integer seconds)
date +%s > /tmp/task_start_time
TASK_START=$(cat /tmp/task_start_time)
echo "Task start timestamp: $TASK_START"

# Create required directories as user ga
su - ga -c "mkdir -p /home/ga/Fiji_Data/raw/gel"
su - ga -c "mkdir -p /home/ga/Fiji_Data/results/gel"

# Clean any previous results to ensure clean state
rm -f /home/ga/Fiji_Data/results/gel/band_quantification.csv 2>/dev/null || true
rm -f /home/ga/Fiji_Data/results/gel/lane_profiles.png 2>/dev/null || true
rm -f /home/ga/Fiji_Data/results/gel/densitometry_report.txt 2>/dev/null || true
rm -f /tmp/gel_result.json 2>/dev/null || true
echo "Previous results cleaned"

# Download the real ImageJ gel electrophoresis sample image
echo "Downloading gel image..."
wget -q --timeout=60 "https://imagej.nih.gov/ij/images/gel.gif" -O /tmp/gel_raw.gif 2>&1 || \
wget -q --timeout=60 "https://imagej.net/images/gel.gif" -O /tmp/gel_raw.gif 2>&1 || \
wget -q --timeout=60 "https://imagej.nih.gov/ij/images/gel.gif" -O /tmp/gel_raw.gif || true

# Convert GIF to TIFF using Python PIL (if download succeeded)
python3 << 'PYEOF'
import os
import sys

gif_path = '/tmp/gel_raw.gif'
tif_path = '/home/ga/Fiji_Data/raw/gel/protein_gel.tif'

try:
    from PIL import Image
    if os.path.exists(gif_path) and os.path.getsize(gif_path) > 1000:
        img = Image.open(gif_path)
        img = img.convert('L')  # convert to grayscale (8-bit)
        img.save(tif_path)
        print(f'Saved gel image: {img.size[0]}x{img.size[1]} pixels -> {tif_path}')
    else:
        print(f'GIF not found or too small at {gif_path}, will use Fiji built-in sample')
        # Write a note for the agent
        note_path = '/home/ga/Fiji_Data/raw/gel/DOWNLOAD_NOTE.txt'
        with open(note_path, 'w') as f:
            f.write('Gel image download failed or file missing.\n')
            f.write('Use Fiji built-in sample: File > Open Samples > Gel\n')
            f.write('Then save as protein_gel.tif or proceed directly with analysis.\n')
except ImportError:
    print('PIL not available, trying alternative conversion...')
    # Fallback: try using convert (ImageMagick) if available
    ret = os.system(f'convert {gif_path} -colorspace Gray {tif_path} 2>/dev/null')
    if ret == 0 and os.path.exists(tif_path):
        print(f'Converted with ImageMagick -> {tif_path}')
    else:
        print('ImageMagick conversion also failed')
        note_path = '/home/ga/Fiji_Data/raw/gel/DOWNLOAD_NOTE.txt'
        with open(note_path, 'w') as f:
            f.write('Gel image download and conversion failed.\n')
            f.write('Use Fiji built-in sample: File > Open Samples > Gel\n')
            f.write('Then proceed with gel analysis workflow.\n')
except Exception as e:
    print(f'Error converting gel image: {e}')
    note_path = '/home/ga/Fiji_Data/raw/gel/DOWNLOAD_NOTE.txt'
    with open(note_path, 'w') as f:
        f.write(f'Gel image conversion error: {e}\n')
        f.write('Use Fiji built-in sample: File > Open Samples > Gel\n')
PYEOF

# Fix ownership
chown -R ga:ga /home/ga/Fiji_Data/raw/gel/ 2>/dev/null || true

# Write gel information file for the agent
cat > /home/ga/Fiji_Data/raw/gel/gel_info.txt << 'INFOEOF'
# Gel Electrophoresis Image Information
# Image type: SDS-PAGE protein gel, Coomassie blue staining
# Image source: ImageJ sample library (real laboratory gel)
#
# Gel characteristics:
# - Multiple protein samples in separate lanes
# - Darker areas = higher protein concentration
# - Lane 1 (leftmost): reference/loading control lane
# - Analysis: measure relative band intensity per lane
#
# Fiji gel analysis workflow:
# 1. Open: File > Open > ~/Fiji_Data/raw/gel/protein_gel.tif
#    (or File > Open Samples > Gel if file missing)
# 2. Check orientation: darker = more protein (invert if needed)
#    Edit > Invert (Ctrl+Shift+I) if bands appear bright on dark
# 3. Draw rectangle around Lane 1
# 4. Analyze > Gels > Select First Lane (or press '1')
# 5. Move rectangle to Lane 2
# 6. Analyze > Gels > Select Next Lane (or press '2')
# 7. Repeat step 5-6 for all remaining lanes
# 8. Analyze > Gels > Plot Lanes (or press '3')
# 9. In profile plot: Analyze > Gels > Label Peaks
# 10. Results table shows % area per peak = band intensity
#
# For normalization:
# - Lane 1 is reference (normalized = 1.0)
# - normalized_intensity = lane_N_intensity / lane_1_intensity
#
# NOTE: If Analyze > Gels is grayed out:
# - Make sure the gel image is the active window
# - Draw a rectangular selection first (R key)
# - The image must be a grayscale (8-bit or 16-bit)
#
# Output files needed:
# - ~/Fiji_Data/results/gel/band_quantification.csv
# - ~/Fiji_Data/results/gel/lane_profiles.png
# - ~/Fiji_Data/results/gel/densitometry_report.txt
INFOEOF

chown ga:ga /home/ga/Fiji_Data/raw/gel/gel_info.txt 2>/dev/null || true

# Write baseline marker for do-nothing detection
echo "0" > /tmp/initial_gel_lanes

# List what was set up
echo "Contents of ~/Fiji_Data/raw/gel/:"
ls -lh /home/ga/Fiji_Data/raw/gel/ 2>/dev/null || echo "(directory empty)"

# Launch Fiji as user ga
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
sleep 10

# Wait for Fiji window to appear
echo "Waiting for Fiji window..."
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "fiji\|imagej" > /dev/null 2>&1; then
        echo "Fiji window detected at ${elapsed}s"
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

if [ $elapsed -ge $timeout ]; then
    echo "WARNING: Fiji window not detected after ${timeout}s, continuing anyway"
fi

# Maximize Fiji window
DISPLAY=:1 wmctrl -r "fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true

sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/fiji_gel_setup_start.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/fiji_gel_setup_start.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Fiji is ready for gel electrophoresis densitometry task"
echo "Gel image: /home/ga/Fiji_Data/raw/gel/protein_gel.tif"
echo "Output dir: /home/ga/Fiji_Data/results/gel/"
