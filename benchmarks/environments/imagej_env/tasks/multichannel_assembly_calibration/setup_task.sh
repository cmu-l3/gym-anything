#!/bin/bash
# Setup script for multichannel_assembly_calibration task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Multi-Channel Assembly Task ==="

# Define paths
RAW_DIR="/home/ga/ImageJ_Data/raw/experiment_042"
PROCESSED_DIR="/home/ga/ImageJ_Data/processed"
METADATA_FILE="$RAW_DIR/microscope_metadata.txt"

# Clean and create directories
rm -rf "$RAW_DIR" 2>/dev/null || true
mkdir -p "$RAW_DIR"
mkdir -p "$PROCESSED_DIR"
chown -R ga:ga "/home/ga/ImageJ_Data"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create metadata file
echo "Microscope Metadata - Experiment 042" > "$METADATA_FILE"
echo "Date: 2023-10-15" >> "$METADATA_FILE"
echo "Objective: 63x/1.4 Oil" >> "$METADATA_FILE"
echo "Camera: sCMOS" >> "$METADATA_FILE"
echo "Pixel Size: 0.16 microns" >> "$METADATA_FILE"
echo "Channels: 3" >> "$METADATA_FILE"
chown ga:ga "$METADATA_FILE"

# Prepare data generation macro
# We will use the 'Fluorescent Cells' sample, split it, strip metadata, and save channels
DATA_GEN_MACRO="/tmp/generate_channels.ijm"
cat > "$DATA_GEN_MACRO" << 'MACROEOF'
// Open sample image
run("Fluorescent Cells (400K)");

// Ensure it's RGB
run("RGB Color");

// Split channels
run("Split Channels");

// Process Red Channel (becomes Mitochondria)
selectWindow("Fluorescent Cells (400K) (red)");
run("Properties...", "unit=pixel pixel_width=1 pixel_height=1 voxel_depth=1");
saveAs("Tiff", "/home/ga/ImageJ_Data/raw/experiment_042/mitochondria_raw.tif");
close();

// Process Green Channel (becomes Cytoskeleton)
selectWindow("Fluorescent Cells (400K) (green)");
run("Properties...", "unit=pixel pixel_width=1 pixel_height=1 voxel_depth=1");
// Make it a bit dim to require contrast adjustment
run("Multiply...", "value=0.4");
saveAs("Tiff", "/home/ga/ImageJ_Data/raw/experiment_042/cytoskeleton_raw.tif");
close();

// Process Blue Channel (becomes Nucleus)
selectWindow("Fluorescent Cells (400K) (blue)");
run("Properties...", "unit=pixel pixel_width=1 pixel_height=1 voxel_depth=1");
saveAs("Tiff", "/home/ga/ImageJ_Data/raw/experiment_042/nucleus_raw.tif");
close();

eval("script", "System.exit(0);");
MACROEOF

# Run Fiji to generate data
echo "Generating raw channel data..."
FIJI_PATH=$(find_fiji_executable)
timeout 60s "$FIJI_PATH" --headless -macro "$DATA_GEN_MACRO" > /dev/null 2>&1

# Verify data generation
if [ ! -f "$RAW_DIR/nucleus_raw.tif" ]; then
    echo "ERROR: Data generation failed"
    # Fallback: create dummy files if Fiji fails (shouldn't happen in valid env)
    convert -size 512x512 xc:black "$RAW_DIR/nucleus_raw.tif"
    convert -size 512x512 xc:gray20 "$RAW_DIR/cytoskeleton_raw.tif"
    convert -size 512x512 xc:gray40 "$RAW_DIR/mitochondria_raw.tif"
fi

# Set permissions
chown -R ga:ga "$RAW_DIR"

# Launch Fiji for the agent
echo "Launching Fiji for user..."
kill_fiji 2>/dev/null || true
launch_fiji

# Wait for Fiji
wait_for_fiji 60
WID=$(get_fiji_window_id)
maximize_window "$WID"

# Open the raw directory in file manager for convenience (optional, but helpful)
su - ga -c "DISPLAY=:1 xdg-open '$RAW_DIR' &"

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="