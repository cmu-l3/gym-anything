#!/bin/bash
set -e
echo "=== Setting up ROI Curation Task ==="

# 1. Directories and Permissions
TASK_DIR="/home/ga/Fiji_Data/curation"
mkdir -p "$TASK_DIR"
chown ga:ga "$TASK_DIR"

# 2. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Prepare Image Data (BBBC005)
# We use a specific image from the environment samples if available, or download one
SOURCE_IMG_DIR="/opt/fiji_samples/BBBC005"
# Try to find a TIF file
SOURCE_IMG=$(find "$SOURCE_IMG_DIR" -name "*w1*.TIF" | head -n 1)

if [ -z "$SOURCE_IMG" ]; then
    echo "Downloading sample image..."
    # Fallback download if local sample missing
    wget -q -O "$TASK_DIR/training_image.tif" "https://data.broadinstitute.org/bbbc/BBBC005/BBBC005_v1_images/SIMCEP_images_A05_C26_F1_s05_w1.TIF" || \
    wget -q -O "$TASK_DIR/training_image.tif" "https://imagej.nih.gov/ij/images/blobs.gif"
else
    cp "$SOURCE_IMG" "$TASK_DIR/training_image.tif"
fi

# Ensure image exists and is readable
if [ ! -f "$TASK_DIR/training_image.tif" ]; then
    echo "ERROR: Failed to prepare training image."
    exit 1
fi
chmod 666 "$TASK_DIR/training_image.tif"

# 4. Generate "Bad" ROIs using a Fiji Macro
# This macro creates the 'automated_segmentation.zip' with specific errors
MACRO_FILE="/tmp/generate_rois.ijm"
INFO_FILE="/tmp/roi_ground_truth_info.json"

cat > "$MACRO_FILE" << EOF
// Open image
open("$TASK_DIR/training_image.tif");
run("Set Scale...", "distance=0 known=0 pixel=1 unit=pixel");

// Auto segment to get base cells
run("Auto Threshold", "method=Otsu white");
run("Analyze Particles...", "size=50-Infinity exclude add");

// --- CREATE ERRORS ---

// 1. Create False Positive (Noise) at (15, 15)
makeOval(5, 5, 20, 20); 
roiManager("Add");
noise_idx = roiManager("count") - 1;
roiManager("Select", noise_idx);
roiManager("Rename", "False_Positive_Noise");

// 2. Create Merged Error
// Select first two valid cells (assuming > 2 cells exist)
count = roiManager("count");
if (count > 3) {
    // Select indices 0 and 1 (skipping the noise we just added at end)
    roiManager("Select", newArray(0, 1));
    
    // Get their combined center for verification later
    run("Measure"); 
    // (Measurement logic handled in bash via python after saving, simpler)
    
    // Merge them
    roiManager("Combine");
    roiManager("Add");
    
    merge_idx = roiManager("count") - 1;
    roiManager("Select", merge_idx);
    roiManager("Rename", "Merged_Error");
    
    // Delete the original separate ones
    roiManager("Select", newArray(0, 1));
    roiManager("Delete");
}

// Save the messy set
roiManager("Deselect");
roiManager("Save", "$TASK_DIR/automated_segmentation.zip");

// Save info about the merge location for verification
// We select the merged ROI and measure it
n = roiManager("count");
roiManager("Select", n-1); // The merged one is likely last
getSelectionBounds(x, y, w, h);
centerX = x + w/2;
centerY = y + h/2;

print("Merge_X:" + centerX);
print("Merge_Y:" + centerY);

run("Quit");
EOF

echo "Running Fiji macro to generate bad ROIs..."
# Run headless
/usr/local/bin/fiji --headless --console -macro "$MACRO_FILE" > /tmp/fiji_setup_output.txt 2>&1

# Extract Merge coordinates from output
MERGE_X=$(grep "Merge_X:" /tmp/fiji_setup_output.txt | cut -d':' -f2 | tr -d '\r')
MERGE_Y=$(grep "Merge_Y:" /tmp/fiji_setup_output.txt | cut -d':' -f2 | tr -d '\r')

# Default if extraction failed
if [ -z "$MERGE_X" ]; then MERGE_X="0"; fi
if [ -z "$MERGE_Y" ]; then MERGE_Y="0"; fi

# Save ground truth info
cat > "$INFO_FILE" << JSONEOF
{
    "noise_coords": [15, 15],
    "noise_radius": 20,
    "merge_coords": [$MERGE_X, $MERGE_Y],
    "merge_radius": 50
}
JSONEOF

echo "Ground truth info saved to $INFO_FILE"

# 5. Clean up previous results
rm -f "$TASK_DIR/curated_ground_truth.zip" 2>/dev/null || true

# 6. Set correct permissions
chown ga:ga "$TASK_DIR"/*
chmod 644 "$TASK_DIR"/*

# 7. Launch Fiji for the user (Clean State)
echo "Launching Fiji GUI..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej"; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="