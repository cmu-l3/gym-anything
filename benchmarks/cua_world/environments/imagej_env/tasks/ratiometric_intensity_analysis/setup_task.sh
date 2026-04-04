#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Ratiometric Intensity Analysis Task ==="

# 1. Prepare directories
RESULTS_DIR="/home/ga/ImageJ_Data/results"
GT_DIR="/tmp/task_ground_truth"

mkdir -p "$RESULTS_DIR"
mkdir -p "$GT_DIR"
# Ensure user owns the results dir
chown -R ga:ga "/home/ga/ImageJ_Data"

# 2. Clear previous results
rm -f "$RESULTS_DIR/ratio_map.tif"
rm -f "$RESULTS_DIR/mean_ratio.txt"
rm -f /tmp/task_result.json

# 3. Generate Ground Truth Source Data
# We use Fiji in headless mode to extract the raw Red and Green channels from the built-in sample.
# This ensures we are comparing against the exact same image the user sees.
echo "Generating ground truth source data..."

GT_MACRO="$GT_DIR/extract_channels.ijm"
cat > "$GT_MACRO" << 'EOF'
// Open the standard sample
run("Fluorescent Cells (400K)");
// Split channels
run("Split Channels");
// Save Red (C1)
selectWindow("C1-Fluorescent Cells (400K)");
saveAs("Tiff", "/tmp/task_ground_truth/red_channel.tif");
// Save Green (C2)
selectWindow("C2-Fluorescent Cells (400K)");
saveAs("Tiff", "/tmp/task_ground_truth/green_channel.tif");
// Close everything
run("Close All");
eval("script", "System.exit(0);");
EOF

# Find Fiji
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found"
    exit 1
fi

# Run headless to extract channels
# Note: XVFB or existing display might be needed even for --headless on some systems, 
# but usually --headless works without. If it fails, we assume standard image properties.
"$FIJI_PATH" --headless -macro "$GT_MACRO" > /tmp/gt_generation.log 2>&1 || echo "Warning: Headless macro failed, verification will rely on strict file checks."

# 4. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch Fiji for the user
echo "Launching Fiji..."
kill_fiji 2>/dev/null || true
sleep 1
launch_fiji

# 6. Wait for Fiji to be ready
wait_for_fiji 60

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="