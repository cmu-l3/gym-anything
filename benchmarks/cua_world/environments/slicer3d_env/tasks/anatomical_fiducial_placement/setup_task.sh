#!/bin/bash
echo "=== Setting up Anatomical Landmark Fiducial Placement Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Prepare BraTS data (downloads real data if not exists)
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh

# Get the actual sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

SAMPLE_DIR="$BRATS_DIR/$SAMPLE_ID"
FLAIR_FILE="$SAMPLE_DIR/${SAMPLE_ID}_flair.nii.gz"

echo "Using sample: $SAMPLE_ID"

# Verify FLAIR file exists
if [ ! -f "$FLAIR_FILE" ]; then
    echo "ERROR: FLAIR volume not found at $FLAIR_FILE"
    exit 1
fi
echo "FLAIR volume found: $FLAIR_FILE"

# Record initial state and task start time
date +%s > /tmp/task_start_time.txt
rm -f /tmp/fiducial_task_result.json 2>/dev/null || true
rm -f "$BRATS_DIR/navigation_landmarks.mrk.json" 2>/dev/null || true
rm -f "$BRATS_DIR/landmarks_screenshot.png" 2>/dev/null || true

# Create ground truth landmark positions based on volume geometry
echo "Computing expected landmark positions from volume geometry..."
python3 << PYEOF
import json
import os
import sys

try:
    import nibabel as nib
    import numpy as np
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "numpy"])
    import nibabel as nib
    import numpy as np

flair_path = "$FLAIR_FILE"
gt_dir = "$GROUND_TRUTH_DIR"
sample_id = "$SAMPLE_ID"

# Load FLAIR to get volume geometry
nii = nib.load(flair_path)
data = nii.get_fdata()
affine = nii.affine
header = nii.header

# Get volume dimensions and spacing
dims = data.shape
spacing = header.get_zooms()[:3]

print(f"Volume dimensions: {dims}")
print(f"Voxel spacing: {spacing}")

# Calculate physical extent of volume
extent = [d * s for d, s in zip(dims, spacing)]
print(f"Physical extent (mm): {extent}")

# Get origin from affine matrix
origin = affine[:3, 3]
print(f"Origin: {origin}")

# Calculate physical coordinate ranges
# In RAS coordinates (Right-Anterior-Superior):
# - X: Left(-) to Right(+)
# - Y: Posterior(-) to Anterior(+)  
# - Z: Inferior(-) to Superior(+)

# Volume center in voxel coordinates
center_voxel = np.array(dims) / 2.0

# Convert center to physical (RAS) coordinates
center_physical = nib.affines.apply_affine(affine, center_voxel)
print(f"Center (physical): {center_physical}")

# Calculate bounds in physical coordinates
corner_000 = nib.affines.apply_affine(affine, [0, 0, 0])
corner_max = nib.affines.apply_affine(affine, [dims[0]-1, dims[1]-1, dims[2]-1])

x_range = sorted([corner_000[0], corner_max[0]])
y_range = sorted([corner_000[1], corner_max[1]])
z_range = sorted([corner_000[2], corner_max[2]])

print(f"X range (L-R): {x_range}")
print(f"Y range (P-A): {y_range}")
print(f"Z range (I-S): {z_range}")

x_extent = x_range[1] - x_range[0]
y_extent = y_range[1] - y_range[0]
z_extent = z_range[1] - z_range[0]

# Define expected landmark positions relative to volume geometry
# These are approximate positions based on typical brain anatomy

# Nasion: Anterior midline, inferior region (bridge of nose)
# In RAS: X=0 (midline), Y=anterior (positive), Z=inferior
nasion_expected = [
    (x_range[0] + x_range[1]) / 2.0,  # Midline
    y_range[1] - 0.05 * y_extent,      # Very anterior (95% of anterior extent)
    z_range[0] + 0.35 * z_extent       # Inferior third
]

# Inion: Posterior midline, mid-level (back of head)
# In RAS: X=0 (midline), Y=posterior (negative), Z=middle-low
inion_expected = [
    (x_range[0] + x_range[1]) / 2.0,  # Midline
    y_range[0] + 0.10 * y_extent,      # Very posterior (10% from back)
    z_range[0] + 0.45 * z_extent       # Mid-inferior
]

# Left Tragus: Left lateral, mid AP, mid SI (left ear)
# In RAS: X=negative (left), Y=middle, Z=middle-low
left_tragus_expected = [
    x_range[0] + 0.10 * x_extent,      # Left side (10% from left edge)
    (y_range[0] + y_range[1]) / 2.0,   # Mid anteroposterior
    z_range[0] + 0.40 * z_extent       # Lower-middle
]

# Right Tragus: Right lateral, mid AP, mid SI (right ear)
# In RAS: X=positive (right), Y=middle, Z=middle-low
right_tragus_expected = [
    x_range[1] - 0.10 * x_extent,      # Right side (10% from right edge)
    (y_range[0] + y_range[1]) / 2.0,   # Mid anteroposterior
    z_range[0] + 0.40 * z_extent       # Lower-middle
]

# Create ground truth file
gt_data = {
    "sample_id": sample_id,
    "volume_dims": list(dims),
    "voxel_spacing_mm": list(spacing),
    "physical_extent_mm": extent,
    "coordinate_system": "RAS",
    "expected_landmarks": {
        "Nasion": {
            "position_ras": nasion_expected,
            "description": "Bridge of nose, anterior midline"
        },
        "Inion": {
            "position_ras": inion_expected,
            "description": "External occipital protuberance, posterior midline"
        },
        "Left_Tragus": {
            "position_ras": left_tragus_expected,
            "description": "Left ear canal opening, lateral"
        },
        "Right_Tragus": {
            "position_ras": right_tragus_expected,
            "description": "Right ear canal opening, lateral"
        }
    },
    "tolerance_mm": 20.0,
    "symmetry_tolerance_mm": 10.0
}

# Save ground truth
os.makedirs(gt_dir, exist_ok=True)
gt_path = os.path.join(gt_dir, f"{sample_id}_landmarks_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth saved to: {gt_path}")
print(f"Expected positions (RAS mm):")
for name, info in gt_data["expected_landmarks"].items():
    pos = info["position_ras"]
    print(f"  {name}: [{pos[0]:.1f}, {pos[1]:.1f}, {pos[2]:.1f}]")
PYEOF

# Verify ground truth was created
GT_FILE="$GROUND_TRUTH_DIR/${SAMPLE_ID}_landmarks_gt.json"
if [ ! -f "$GT_FILE" ]; then
    echo "ERROR: Ground truth landmarks not created!"
    exit 1
fi
echo "Ground truth landmarks verified (hidden from agent)"

# Create a Slicer Python script to load the FLAIR volume
cat > /tmp/load_flair_for_landmarks.py << 'PYEOF'
import slicer
import os

sample_dir = os.environ.get("SAMPLE_DIR", "/home/ga/Documents/SlicerData/BraTS/BraTS2021_00000")
sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")

flair_path = os.path.join(sample_dir, f"{sample_id}_flair.nii.gz")

print(f"Loading FLAIR volume for landmark placement...")
print(f"Path: {flair_path}")

if os.path.exists(flair_path):
    # Load volume
    volume_node = slicer.util.loadVolume(flair_path)
    
    if volume_node:
        volume_node.SetName("Brain_FLAIR")
        
        # Set appropriate window/level for brain MRI
        displayNode = volume_node.GetDisplayNode()
        if displayNode:
            displayNode.SetAutoWindowLevel(True)
        
        # Set as background in all views
        for color in ["Red", "Green", "Yellow"]:
            sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
            sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
        
        # Reset and center views
        slicer.util.resetSliceViews()
        
        # Get volume bounds and center on data
        bounds = [0]*6
        volume_node.GetBounds(bounds)
        
        for color in ["Red", "Green", "Yellow"]:
            sliceWidget = slicer.app.layoutManager().sliceWidget(color)
            sliceLogic = sliceWidget.sliceLogic()
            sliceNode = sliceLogic.GetSliceNode()
            center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
            
            # Set initial slice positions at center
            if color == "Red":  # Axial
                sliceNode.SetSliceOffset(center[2])
            elif color == "Green":  # Sagittal (good for Nasion/Inion)
                sliceNode.SetSliceOffset(center[0])  # Start at midline
            else:  # Coronal
                sliceNode.SetSliceOffset(center[1])
        
        # Set layout to conventional four-up view (good for landmark placement)
        layoutManager = slicer.app.layoutManager()
        layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutConventionalView)
        
        print(f"FLAIR volume loaded successfully")
        print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
        print(f"Ready for anatomical landmark placement")
    else:
        print("ERROR: Could not load FLAIR volume")
else:
    print(f"ERROR: FLAIR file not found at {flair_path}")

print("Setup complete - use Markups module to place fiducial points")
PYEOF

# Set environment variables for the Python script
export SAMPLE_DIR="$SAMPLE_DIR"
export SAMPLE_ID="$SAMPLE_ID"

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with brain MRI..."
sudo -u ga DISPLAY=:1 SAMPLE_DIR="$SAMPLE_DIR" SAMPLE_ID="$SAMPLE_ID" /opt/Slicer/Slicer --python-script /tmp/load_flair_for_landmarks.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window
echo "Configuring Slicer window..."
sleep 3

WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus
    focus_window "$WID"
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/landmarks_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Anatomical Landmark Fiducial Placement"
echo "============================================="
echo ""
echo "You are preparing a brain MRI for surgical navigation."
echo "Place fiducial markers at 4 anatomical landmarks."
echo ""
echo "Required landmarks:"
echo "  1. Nasion - Bridge of nose (anterior midline)"
echo "     Use sagittal view, look at front of head"
echo ""
echo "  2. Inion - Back of head (posterior midline)"
echo "     Use sagittal view, look at back of head"
echo ""
echo "  3. Left_Tragus - Left ear canal opening"
echo "     Use axial view, look at left side"
echo ""
echo "  4. Right_Tragus - Right ear canal opening"
echo "     Use axial view, look at right side"
echo ""
echo "Steps:"
echo "  1. Go to Markups module"
echo "  2. Create a Point List named 'Navigation_Landmarks'"
echo "  3. Place 4 fiducial points at the landmarks"
echo "  4. Rename each point with its anatomical name"
echo "  5. Save to: ~/Documents/SlicerData/BraTS/navigation_landmarks.mrk.json"
echo "  6. Take screenshot: ~/Documents/SlicerData/BraTS/landmarks_screenshot.png"
echo ""