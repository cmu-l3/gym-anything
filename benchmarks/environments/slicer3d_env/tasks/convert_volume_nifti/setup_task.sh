#!/bin/bash
echo "=== Setting up Convert Volume to NIfTI Format task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Define paths
SAMPLE_DIR="/home/ga/Documents/SlicerData/SampleData"
SOURCE_FILE="$SAMPLE_DIR/MRHead.nrrd"
OUTPUT_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_FILE="$OUTPUT_DIR/MRHead_converted.nii.gz"

# Ensure directories exist
mkdir -p "$SAMPLE_DIR"
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Check if sample data exists, download if needed
if [ ! -f "$SOURCE_FILE" ] || [ "$(stat -c%s "$SOURCE_FILE" 2>/dev/null || echo 0)" -lt 1000000 ]; then
    echo "Sample file not found or too small, downloading..."
    
    # Try multiple download URLs
    DOWNLOAD_SUCCESS=false
    
    # URL 1: GitHub releases
    if ! $DOWNLOAD_SUCCESS; then
        curl -L -o "$SOURCE_FILE" --connect-timeout 30 --max-time 120 \
            "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
        if [ -f "$SOURCE_FILE" ] && [ "$(stat -c%s "$SOURCE_FILE" 2>/dev/null || echo 0)" -gt 1000000 ]; then
            DOWNLOAD_SUCCESS=true
            echo "Downloaded MRHead.nrrd from GitHub"
        fi
    fi
    
    # URL 2: Kitware data
    if ! $DOWNLOAD_SUCCESS; then
        wget --timeout=120 -O "$SOURCE_FILE" \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null
        if [ -f "$SOURCE_FILE" ] && [ "$(stat -c%s "$SOURCE_FILE" 2>/dev/null || echo 0)" -gt 1000000 ]; then
            DOWNLOAD_SUCCESS=true
            echo "Downloaded MRHead.nrrd from Kitware"
        fi
    fi
    
    if ! $DOWNLOAD_SUCCESS; then
        echo "WARNING: Could not download sample data"
    fi
fi

# Verify source file
if [ -f "$SOURCE_FILE" ]; then
    SOURCE_SIZE=$(stat -c%s "$SOURCE_FILE" 2>/dev/null || echo "0")
    echo "Source file: $SOURCE_FILE ($SOURCE_SIZE bytes)"
else
    echo "ERROR: Source file not found at $SOURCE_FILE"
fi

# Record source file properties for verification
python3 << 'PYEOF'
import json
import os
import sys

source_path = "/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"
output_path = "/home/ga/Documents/SlicerData/Exports/MRHead_converted.nii.gz"

source_info = {
    "source_path": source_path,
    "source_exists": os.path.exists(source_path),
    "source_size_bytes": os.path.getsize(source_path) if os.path.exists(source_path) else 0,
    "output_path": output_path,
    "output_exists_before": os.path.exists(output_path),
    "dimensions": None,
    "spacing": None
}

# Try to get source file properties
if source_info["source_exists"]:
    try:
        # Try nrrd library first
        try:
            import nrrd
            data, header = nrrd.read(source_path)
            source_info["dimensions"] = list(data.shape)
            if 'space directions' in header:
                # Extract spacing from space directions
                import numpy as np
                sd = header['space directions']
                spacing = [np.linalg.norm(sd[i]) for i in range(len(sd)) if sd[i] is not None]
                source_info["spacing"] = spacing
            elif 'spacings' in header:
                source_info["spacing"] = list(header['spacings'])
        except ImportError:
            # Fallback: try nibabel (it can read some NRRD files)
            import nibabel as nib
            img = nib.load(source_path)
            source_info["dimensions"] = list(img.shape)
            source_info["spacing"] = list(img.header.get_zooms()[:3])
    except Exception as e:
        print(f"Warning: Could not read source properties: {e}", file=sys.stderr)

# Save source info
with open("/tmp/source_file_info.json", "w") as f:
    json.dump(source_info, f, indent=2)

print("Source file info:")
print(json.dumps(source_info, indent=2))
PYEOF

# Clean up any previous output (ensure fresh task)
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing previous output file..."
    rm -f "$OUTPUT_FILE"
fi

# Record initial output directory state
ls -la "$OUTPUT_DIR" 2>/dev/null > /tmp/initial_output_dir.txt || true
echo "0" > /tmp/initial_output_count.txt
find "$OUTPUT_DIR" -name "*.nii*" -type f 2>/dev/null | wc -l > /tmp/initial_nifti_count.txt || echo "0" > /tmp/initial_nifti_count.txt

# Set permissions
chown -R ga:ga /home/ga/Documents/SlicerData
chmod -R 755 /home/ga/Documents/SlicerData

# Launch 3D Slicer with empty scene
echo "Launching 3D Slicer..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
for i in {1..60}; do
    if pgrep -f "Slicer" > /dev/null && DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected after ${i}s"
        break
    fi
    sleep 1
done

# Additional wait for Slicer to fully initialize
sleep 5

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Convert the MRHead.nrrd volume to NIfTI format"
echo ""
echo "Source file: $SOURCE_FILE"
echo "Expected output: $OUTPUT_FILE"
echo ""
echo "Steps:"
echo "  1. Load MRHead.nrrd via File > Add Data"
echo "  2. File > Save Data (or Ctrl+S)"
echo "  3. Change format from .nrrd to .nii.gz"
echo "  4. Set output path to ~/Documents/SlicerData/Exports/MRHead_converted.nii.gz"
echo "  5. Click Save"