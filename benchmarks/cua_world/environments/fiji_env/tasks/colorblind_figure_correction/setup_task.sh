#!/bin/bash
set -e
echo "=== Setting up Colorblind Figure Correction task ==="

# Source utilities if available, otherwise define basics
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Create directory structure
mkdir -p /home/ga/Fiji_Data/raw/composite
mkdir -p /home/ga/Fiji_Data/results/figures
chown -R ga:ga /home/ga/Fiji_Data

# 2. Generate the "unsafe" Red/Green composite image from existing sample data
# We use the BBBC005 synthetic cells available in the environment
echo "Generating unsafe composite image..."
python3 << 'PYEOF'
import os
import numpy as np
import glob
from PIL import Image, ImageOps

# Source directory for samples
source_dir = "/home/ga/Fiji_Data/raw/BBBC005"
output_path = "/home/ga/Fiji_Data/raw/composite/unsafe_composite.tif"

# Find a pair of images (w1 and w2)
w1_files = sorted(glob.glob(os.path.join(source_dir, "*w1*.TIF")))
w2_files = sorted(glob.glob(os.path.join(source_dir, "*w2*.TIF")))

if w1_files and w2_files:
    # Use the first matching pair
    img1 = Image.open(w1_files[0]).convert('L')
    img2 = Image.open(w2_files[0]).convert('L')
    
    # Resize to something manageable if too huge, though BBBC005 is small
    # Ensure they are the same size
    img2 = img2.resize(img1.size)
    
    # Create a multi-page TIFF to simulate a composite
    # In Fiji, a 2-channel image is often a stack with metadata
    # We will save as a multi-page TIFF which Fiji interprets as a stack/composite
    img1.save(
        output_path, 
        save_all=True, 
        append_images=[img2], 
        compression=None
    )
    print(f"Created composite from {w1_files[0]} and {w2_files[0]}")
else:
    # Fallback if samples missing: Generate synthetic
    print("Sample data not found, generating synthetic pattern...")
    width, height = 512, 512
    
    # Channel 1: Circles (Nuclei)
    arr1 = np.zeros((height, width), dtype=np.uint8)
    for i in range(50, 450, 100):
        for j in range(50, 450, 100):
            y, x = np.ogrid[-i:height-i, -j:width-j]
            mask = x*x + y*y <= 30*30
            arr1[mask] = 200
            
    # Channel 2: Lines/Cytoskeleton
    arr2 = np.zeros((height, width), dtype=np.uint8)
    for i in range(0, 512, 20):
        arr2[i:i+5, :] = 150
        
    img1 = Image.fromarray(arr1)
    img2 = Image.fromarray(arr2)
    img1.save(output_path, save_all=True, append_images=[img2])

# Set permissions
os.chmod(output_path, 0o666)
PYEOF

# 3. Create a Fiji macro to set the Lookup Tables (LUTs) to Red/Green explicitly upon opening
# This ensures the agent sees the "bad" state (Red/Green) when they open it.
# However, we can't easily force Fiji to open it with specific LUTs unless we save it as a hyperstack 
# with metadata. The python script above saves a generic multi-page TIFF.
# Fiji usually defaults to grayscale.
# To make this robust, we will create a startup macro or just rely on the description saying 
# "Channel 1 is Red, Channel 2 is Green" and the user might need to set it, 
# OR (better) we construct the task such that the file *appears* Red/Green.
# 
# For simplicity in this environment, we will assume the user opens it and sees grayscale 
# or default colors, but the TASK INSTRUCTION says "Channel 1 is Red...". 
# Actually, the task says "Convert A to B".
# 
# Let's write a small helper macro that opens the image and sets the LUTs, 
# saving the agent that step, so they start in the "problem" state.
cat > /home/ga/Desktop/Open_Task_Image.ijm << 'MACRO'
open("/home/ga/Fiji_Data/raw/composite/unsafe_composite.tif");
run("Make Composite");
Stack.setChannel(1);
run("Red");
Stack.setChannel(2);
run("Green");
MACRO
chown ga:ga /home/ga/Desktop/Open_Task_Image.ijm
chmod +x /home/ga/Desktop/Open_Task_Image.ijm

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Clean up previous results
rm -f /home/ga/Fiji_Data/results/figures/*.png

# 6. Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej"; then
        echo "Fiji detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take setup screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="