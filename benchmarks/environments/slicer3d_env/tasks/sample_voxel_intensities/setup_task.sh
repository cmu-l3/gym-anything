#!/bin/bash
echo "=== Setting up Sample Voxel Intensities Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Set environment variables for data preparation
export AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
export GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
export CASE_ID="amos_0001"

# Create directories
mkdir -p "$AMOS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData 2>/dev/null || true

# Prepare AMOS abdominal CT data
echo "Preparing abdominal CT data..."
bash /workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Verify CT file exists
CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT data not found at $CT_FILE"
    exit 1
fi
echo "CT data ready: $CT_FILE ($(du -h "$CT_FILE" | cut -f1))"

# Clean up any previous task output
OUTPUT_FILE="/home/ga/Documents/SlicerData/intensity_measurements.txt"
rm -f "$OUTPUT_FILE" 2>/dev/null || true
echo "0" > /tmp/initial_output_exists.txt

# Record initial state
echo "Recording initial state..."
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "ct_file_exists": true,
    "output_file_exists": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure Slicer is installed
if [ ! -x /opt/Slicer/Slicer ]; then
    echo "ERROR: 3D Slicer not installed"
    exit 1
fi

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the CT volume
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer "$CT_FILE" > /tmp/slicer_launch.log 2>&1 &
SLICER_PID=$!

# Wait for Slicer to fully load
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 120

# Additional wait for volume to render
sleep 5

# Maximize and focus Slicer window
SLICER_WID=$(get_slicer_window_id)
if [ -n "$SLICER_WID" ]; then
    echo "Focusing Slicer window: $SLICER_WID"
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
else
    echo "Warning: Could not find Slicer window ID"
fi

# Take screenshot of initial state
sleep 2
take_screenshot /tmp/task_initial_state.png ga
echo "Initial screenshot saved"

# Verify Slicer is running with CT loaded
TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if echo "$TITLE" | grep -qi "slicer"; then
    echo "3D Slicer is running"
else
    echo "Warning: Could not verify Slicer window title: $TITLE"
fi

# Pre-compute ground truth intensity values for verification
echo "Computing ground truth intensity values..."
python3 << 'PYEOF'
import os
import json
import numpy as np
import sys

# Ensure nibabel is available
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

case_id = os.environ.get("CASE_ID", "amos_0001")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
gt_json_path = os.path.join(gt_dir, f"{case_id}_intensity_gt.json")

print(f"Loading CT from: {ct_path}")

try:
    nii = nib.load(ct_path)
    data = nii.get_fdata()
    spacing = nii.header.get_zooms()[:3]
    print(f"CT shape: {data.shape}, spacing: {spacing}")
except Exception as e:
    print(f"Error loading CT: {e}")
    sys.exit(1)

# Load label map if exists to find organ centroids
label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")
labels = None
if os.path.exists(label_path):
    try:
        labels = nib.load(label_path).get_fdata().astype(np.int32)
        print(f"Loaded label map from {label_path}")
    except Exception as e:
        print(f"Could not load labels: {e}")

ground_truth = {
    "case_id": case_id,
    "ct_shape": [int(x) for x in data.shape],
    "spacing_mm": [float(s) for s in spacing],
    "measurements": {}
}

# Define organ labels (AMOS convention: 10=aorta, 6=liver, 1=spleen)
organs = {
    "aorta": {"label": 10, "expected_range": [150, 250]},
    "liver": {"label": 6, "expected_range": [40, 80]},
    "spleen": {"label": 1, "expected_range": [40, 60]}
}

for organ_name, info in organs.items():
    if labels is not None:
        mask = (labels == info["label"])
        if np.any(mask):
            # Find centroid of organ
            coords = np.argwhere(mask)
            centroid = coords.mean(axis=0).astype(int)
            
            # Sample mean intensity in a small region around centroid
            r = 3  # radius in voxels
            x, y, z = centroid
            x_slice = slice(max(0, x-r), min(data.shape[0], x+r+1))
            y_slice = slice(max(0, y-r), min(data.shape[1], y+r+1))
            z_slice = slice(max(0, z-r), min(data.shape[2], z+r+1))
            
            region = data[x_slice, y_slice, z_slice]
            mean_hu = float(np.mean(region))
            std_hu = float(np.std(region))
            
            ground_truth["measurements"][organ_name] = {
                "centroid_ijk": [int(x), int(y), int(z)],
                "centroid_mm": [float(x * spacing[0]), float(y * spacing[1]), float(z * spacing[2])],
                "mean_hu": round(mean_hu, 1),
                "std_hu": round(std_hu, 1),
                "expected_range": info["expected_range"],
                "tolerance": 30,
                "voxel_count": int(np.sum(mask))
            }
            print(f"{organ_name}: centroid=({x},{y},{z}), HU={mean_hu:.1f}±{std_hu:.1f}")
        else:
            print(f"Warning: No voxels found for {organ_name} (label {info['label']})")
            # Use expected range midpoint as fallback
            mid_hu = (info["expected_range"][0] + info["expected_range"][1]) / 2
            ground_truth["measurements"][organ_name] = {
                "mean_hu": mid_hu,
                "expected_range": info["expected_range"],
                "tolerance": 30,
                "fallback": True
            }
    else:
        print(f"Warning: No label map available for {organ_name}")
        # Use expected range midpoint as fallback
        mid_hu = (info["expected_range"][0] + info["expected_range"][1]) / 2
        ground_truth["measurements"][organ_name] = {
            "mean_hu": mid_hu,
            "expected_range": info["expected_range"],
            "tolerance": 30,
            "fallback": True
        }

# Save ground truth
os.makedirs(gt_dir, exist_ok=True)
with open(gt_json_path, 'w') as f:
    json.dump(ground_truth, f, indent=2)
print(f"\nGround truth saved to: {gt_json_path}")
PYEOF

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "CT Volume: $CT_FILE"
echo "Output file: $OUTPUT_FILE"
echo ""
echo "INSTRUCTIONS:"
echo "1. Enable Data Probe display (View > Data Probe or look at bottom panel)"
echo "2. Navigate to aorta, liver, and spleen in axial view"
echo "3. Position cursor and read HU values from the probe"
echo "4. Save measurements to: $OUTPUT_FILE"
echo ""