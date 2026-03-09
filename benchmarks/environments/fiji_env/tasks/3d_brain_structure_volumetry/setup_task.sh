#!/bin/bash
echo "=== Setting up 3d_brain_structure_volumetry task ==="

# Create required directories
echo "Creating directories..."
mkdir -p /home/ga/Fiji_Data/raw/mri
mkdir -p /home/ga/Fiji_Data/results/volumetry

# Clean previous results for a fresh start
echo "Cleaning previous results..."
rm -f /home/ga/Fiji_Data/results/volumetry/volume_measurements.csv 2>/dev/null || true
rm -f /home/ga/Fiji_Data/results/volumetry/orthogonal_views.tif 2>/dev/null || true
rm -f /home/ga/Fiji_Data/results/volumetry/volumetry_report.txt 2>/dev/null || true

# Record task start timestamp
echo "Recording task start timestamp..."
date +%s > /tmp/task_start_time
TASK_START=$(cat /tmp/task_start_time)
echo "Task start: $TASK_START"

# Download ImageJ MRI stack
echo "Downloading MRI stack..."
MRI_ZIP="/tmp/mri_stack.zip"

if [ ! -f "$MRI_ZIP" ] || [ ! -s "$MRI_ZIP" ]; then
    wget -q --timeout=120 \
        "https://imagej.nih.gov/ij/images/mri-stack.zip" \
        -O "$MRI_ZIP" 2>&1
    WGET_STATUS=$?
    if [ $WGET_STATUS -ne 0 ]; then
        echo "WARNING: Primary download failed (exit $WGET_STATUS). Trying alternate source..."
        wget -q --timeout=120 \
            "https://imagej.net/ij/images/mri-stack.zip" \
            -O "$MRI_ZIP" 2>&1 || true
    fi
else
    echo "MRI stack zip already cached at $MRI_ZIP"
fi

# Extract the MRI stack
if [ -f "$MRI_ZIP" ] && [ -s "$MRI_ZIP" ]; then
    echo "Extracting MRI stack..."
    unzip -q "$MRI_ZIP" -d /home/ga/Fiji_Data/raw/mri/ 2>/dev/null || true

    # Find the extracted file (may be named mri-stack.tif or similar)
    MRI_TIF=$(find /home/ga/Fiji_Data/raw/mri/ -name "*.tif" -o -name "*.TIF" 2>/dev/null | head -1)

    if [ -n "$MRI_TIF" ] && [ "$MRI_TIF" != "/home/ga/Fiji_Data/raw/mri/mri_stack.tif" ]; then
        echo "Renaming extracted file to mri_stack.tif..."
        cp "$MRI_TIF" /home/ga/Fiji_Data/raw/mri/mri_stack.tif 2>/dev/null || true
    fi

    if [ -f "/home/ga/Fiji_Data/raw/mri/mri_stack.tif" ]; then
        SIZE=$(stat -c%s /home/ga/Fiji_Data/raw/mri/mri_stack.tif 2>/dev/null || echo "0")
        echo "MRI stack extracted: mri_stack.tif (${SIZE} bytes)"
    else
        echo "WARNING: Could not find/rename TIFF after extraction."
    fi
else
    echo "WARNING: Could not download MRI stack from imagej.nih.gov."
    echo "NOTE: The MRI Stack is also available in Fiji via File > Open Samples > MRI Stack."
    echo "NOTE: Setup will continue; the agent may use Fiji's built-in MRI Stack sample."
fi

# Write voxel_info.txt
echo "Writing voxel_info.txt..."
cat > /home/ga/Fiji_Data/raw/mri/voxel_info.txt << 'VOXELEOF'
# MRI Stack Voxel Information
# Source: ImageJ Sample Data - Human Brain MRI
# Acquisition: T1-weighted axial scan
# Scanner: Siemens 1.5T
#
# Stack dimensions: 186 x 226 x 27 voxels
# Voxel size:
voxel_width_mm: 1.0
voxel_height_mm: 1.0
voxel_depth_mm: 1.5
bit_depth: 16
n_slices: 27
units: mm
# Analysis notes:
# Brain tissue threshold: approximately 1500-65535 (bright)
# CSF/Ventricles: dark regions within brain mask (~200-800)
VOXELEOF

# Set correct file ownership
echo "Setting file ownership..."
chown -R ga:ga /home/ga/Fiji_Data/ 2>/dev/null || true

# Write initial baseline result JSON (do-nothing baseline = 0 structures, 0 volume)
cat > /tmp/volumetry_result.json << 'JSONEOF'
{
  "task_start": 0,
  "csv_exists": false,
  "csv_modified_after_start": false,
  "n_structures": 0,
  "has_required_columns": false,
  "volumes_mm3": {},
  "all_volumes_positive": false,
  "brain_volume_mm3": 0.0,
  "ventricle_volume_mm3": 0.0,
  "ortho_exists": false,
  "ortho_modified_after_start": false,
  "ortho_size_bytes": 0,
  "report_exists": false,
  "report_modified_after_start": false,
  "report_size_bytes": 0,
  "report_has_brain_keyword": false,
  "report_has_ventricle_keyword": false
}
JSONEOF

# Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
FIJI_PID=$!
sleep 10

# Wait for Fiji window
echo "Waiting for Fiji window..."
TIMEOUT=45
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "fiji\|imagej" > /dev/null 2>&1; then
        echo "Fiji window detected after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Maximize Fiji window
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/fiji_volumetry_setup.png 2>/dev/null || true

# Report setup status
if [ -f "/home/ga/Fiji_Data/raw/mri/mri_stack.tif" ]; then
    SIZE=$(stat -c%s /home/ga/Fiji_Data/raw/mri/mri_stack.tif 2>/dev/null || echo "unknown")
    echo "MRI stack ready: mri_stack.tif (${SIZE} bytes)"
else
    echo "WARNING: mri_stack.tif not found - agent must locate/create the stack"
fi

echo ""
echo "Voxel information:"
cat /home/ga/Fiji_Data/raw/mri/voxel_info.txt

echo ""
echo "=== Setup Complete ==="
echo "MRI stack is at: ~/Fiji_Data/raw/mri/mri_stack.tif"
echo "Voxel info is at: ~/Fiji_Data/raw/mri/voxel_info.txt"
echo "Results should be saved to: ~/Fiji_Data/results/volumetry/"
echo "  - volume_measurements.csv  (brain tissue + ventricle volumes)"
echo "  - orthogonal_views.tif     (XY/XZ/YZ projection composite)"
echo "  - volumetry_report.txt     (summary report with ventricle/brain ratio)"
