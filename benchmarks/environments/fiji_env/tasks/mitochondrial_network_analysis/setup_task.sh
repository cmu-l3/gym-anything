#!/bin/bash
set -e
echo "=== Setting up Mitochondrial Network Analysis Task ==="

# Define paths
DATA_DIR="/home/ga/Fiji_Data/raw/mitochondria"
RESULTS_DIR="/home/ga/Fiji_Data/results/mitochondria"
INPUT_IMAGE="$DATA_DIR/mitochondria_raw.tif"

# Create directories with correct ownership
mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "/home/ga/Fiji_Data"

# Clean previous results
rm -f "$RESULTS_DIR"/*
echo "Cleaned previous results."

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Generate the input image from Fiji's built-in sample
# We use the HeLa cells sample, Channel 2 (Cytoskeleton/Mito-like structure)
# This ensures we have a real biological structure to analyze without external download dependencies.
echo "Generating input image from Fiji samples..."

# Create a macro to extract the sample
cat > /tmp/prepare_image.ijm <<EOF
// Open HeLa Cells sample
run("HeLa Cells (1.3M, 48-bit)");
// Split channels
run("Split Channels");
// Select Channel 2 (Green) which has network-like structures
selectWindow("C2-HeLa Cells (1.3M, 48-bit)");
// Save as TIFF
saveAs("Tiff", "$INPUT_IMAGE");
// Close everything
run("Close All");
eval("script", "System.exit(0);");
EOF

# Run Fiji headless to prepare data
# Try finding the executable
FIJI_EXEC=$(find /opt/fiji -name "ImageJ-linux64" -o -name "fiji-linux64" | head -n 1)
if [ -z "$FIJI_EXEC" ]; then
    FIJI_EXEC="fiji"
fi

echo "Running Fiji macro with $FIJI_EXEC..."
# Run as ga user to ensure file ownership
su - ga -c "$FIJI_EXEC --headless --run /tmp/prepare_image.ijm"

# Verify image creation
if [ -f "$INPUT_IMAGE" ]; then
    echo "Input image created successfully at $INPUT_IMAGE"
else
    echo "ERROR: Failed to create input image."
    exit 1
fi

# Launch Fiji for the user
echo "Launching Fiji GUI..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" > /dev/null 2>&1 &
sleep 10

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ"; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="