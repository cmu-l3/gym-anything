#!/bin/bash
echo "=== Setting up Capture 3D View task ==="

source /workspace/scripts/task_utils.sh

# Ensure sample data exists
SAMPLE_DIR=$(get_sample_data_dir)
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Warning: Sample file not found at $SAMPLE_FILE"
    echo "Attempting to download..."
    mkdir -p "$SAMPLE_DIR"
    wget -q -O "$SAMPLE_FILE" "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null || \
        echo "Could not download sample data"
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Record initial state
SCREENSHOT_DIR=$(get_slicer_screenshot_dir)
mkdir -p "$SCREENSHOT_DIR"
INITIAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l)
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/initial_screenshot_count

# Record timestamps of existing screenshots
ls -la "$SCREENSHOT_DIR"/*.png 2>/dev/null > /tmp/initial_screenshots_list.txt || true

# Clean any previous task results
rm -f /tmp/slicer_3d_task_result.json 2>/dev/null || true

# Launch 3D Slicer
echo "Launching 3D Slicer..."
launch_slicer_with_file "" ga

# Take initial screenshot
sleep 3
take_screenshot /tmp/slicer_3d_initial.png ga

echo "Sample file location: $SAMPLE_FILE"
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"
echo "Screenshot directory: $SCREENSHOT_DIR"
echo "=== Task setup complete ==="
echo ""
echo "TASK: Load MRHead.nrrd, enable 3D volume rendering, and capture a screenshot"
echo "      showing the brain in 3D view."
