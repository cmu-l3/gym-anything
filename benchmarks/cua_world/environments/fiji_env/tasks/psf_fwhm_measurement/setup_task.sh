#!/bin/bash
set -e
echo "=== Setting up PSF FWHM Measurement Task ==="

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# 2. Prepare Directories
RAW_DIR="/home/ga/Fiji_Data/raw/psf_beads"
RESULTS_DIR="/home/ga/Fiji_Data/results/psf"

# Clean up and create directories as 'ga' user to ensure permissions
su - ga -c "rm -rf $RAW_DIR $RESULTS_DIR"
su - ga -c "mkdir -p $RAW_DIR"
su - ga -c "mkdir -p $RESULTS_DIR"

# 3. Locate and Prepare Data (BBBC005)
# We need a Z-slice that is in focus (e.g., z16 for BBBC005 usually)
SOURCE_DIR="/opt/fiji_samples/BBBC005"
BEAD_IMAGE=""

# Search for a suitable image in the installed samples
if [ -d "$SOURCE_DIR" ]; then
    # Look for a file with 'z16' (in focus) and 'w1' (channel 1)
    BEAD_IMAGE=$(find "$SOURCE_DIR" -name "*w1*z16*.TIF" -o -name "*w1*z16*.tif" | head -n 1)
fi

# Fallback if specific slice not found, take any TIF
if [ -z "$BEAD_IMAGE" ] && [ -d "$SOURCE_DIR" ]; then
    BEAD_IMAGE=$(find "$SOURCE_DIR" -name "*.TIF" -o -name "*.tif" | head -n 1)
fi

# Copy the image
TARGET_IMAGE="$RAW_DIR/bead_field.tif"
if [ -n "$BEAD_IMAGE" ]; then
    echo "Using real sample image: $BEAD_IMAGE"
    cp "$BEAD_IMAGE" "$TARGET_IMAGE"
else
    echo "WARNING: BBBC005 samples not found. Downloading fallback blobs sample..."
    wget -q "https://imagej.nih.gov/ij/images/blobs.gif" -O /tmp/blobs.gif
    # Convert GIF to TIF using ImageMagick
    convert /tmp/blobs.gif "$TARGET_IMAGE"
fi

# Set ownership
chown ga:ga "$TARGET_IMAGE"

# 4. Create Calibration Info Text
INFO_FILE="$RAW_DIR/acquisition_info.txt"
cat > "$INFO_FILE" << EOF
Acquisition Parameters
=====================
Microscope: Widefield Fluorescence
Objective: 40x Air (NA 0.75)
Camera Pixel Size: 6.5 µm
Magnification: 40x
Effective Pixel Size: 0.1625 µm/pixel
Image Depth: 16-bit

Calibration Instruction:
Use 'Analyze > Set Scale' in Fiji.
Distance in pixels: 1
Known distance: 0.1625
Unit: um
Global: Checked
EOF
chown ga:ga "$INFO_FILE"

# 5. Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" > /dev/null 2>&1 &
FIJI_PID=$!

# Wait for Fiji to appear
echo "Waiting for Fiji window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Open the image automatically to save the agent one trivial step?
# No, the task description says "Open the bead image", let's let them do it.
# It proves they can navigate the file system.

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="