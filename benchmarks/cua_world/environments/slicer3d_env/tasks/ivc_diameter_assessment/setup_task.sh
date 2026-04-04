#!/bin/bash
echo "=== Setting up IVC Diameter Assessment Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Prepare AMOS data (downloads real data if not exists)
echo "Preparing AMOS 2022 data..."
export CASE_ID GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"
LABELS_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz"

echo "Using case: $CASE_ID"

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    exit 1
fi
echo "CT volume found: $CT_FILE"

# Clean up any previous task outputs
rm -f "$AMOS_DIR/ivc_measurements.mrk.json" 2>/dev/null || true
rm -f "$AMOS_DIR/ivc_report.json" 2>/dev/null || true
rm -f /tmp/ivc_task_result.json 2>/dev/null || true

# Compute IVC ground truth from AMOS labels
echo "Computing IVC ground truth measurements..."
python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

case_id = os.environ.get("CASE_ID", "amos_0001")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
labels_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")

if not os.path.exists(labels_path):
    print(f"Warning: Labels file not found at {labels_path}")
    # Create default ground truth
    gt_data = {
        "case_id": case_id,
        "intrahepatic_diameter_mm": 22.0,
        "infrarenal_diameter_mm": 18.0,
        "classification": "Normal",
        "ivc_bounds": {}
    }
else:
    print(f"Loading labels from {labels_path}")
    labels_nii = nib.load(labels_path)
    labels = labels_nii.get_fdata().astype(np.int16)
    spacing = labels_nii.header.get_zooms()[:3]
    
    # IVC is label 9 in AMOS
    ivc_mask = (labels == 9)
    
    if not np.any(ivc_mask):
        print("Warning: No IVC voxels found in labels, using defaults")
        gt_data = {
            "case_id": case_id,
            "intrahepatic_diameter_mm": 22.0,
            "infrarenal_diameter_mm": 18.0,
            "classification": "Normal",
            "ivc_bounds": {}
        }
    else:
        # Find IVC bounds
        ivc_coords = np.argwhere(ivc_mask)
        ivc_min = ivc_coords.min(axis=0)
        ivc_max = ivc_coords.max(axis=0)
        
        # Compute diameter at each slice
        nz = labels.shape[2]
        slice_diameters = []
        
        for z in range(nz):
            slice_mask = ivc_mask[:, :, z]
            if not np.any(slice_mask):
                continue
            
            # Area-equivalent diameter
            area_pixels = np.sum(slice_mask)
            area_mm2 = area_pixels * spacing[0] * spacing[1]
            equiv_diameter = 2 * np.sqrt(area_mm2 / np.pi)
            
            slice_diameters.append({
                'z': z,
                'diameter_mm': equiv_diameter,
                'area_pixels': int(area_pixels)
            })
        
        if not slice_diameters:
            print("Warning: No valid IVC slices found")
            gt_data = {
                "case_id": case_id,
                "intrahepatic_diameter_mm": 22.0,
                "infrarenal_diameter_mm": 18.0,
                "classification": "Normal",
                "ivc_bounds": {}
            }
        else:
            # Sort by z to find levels
            slice_diameters.sort(key=lambda x: x['z'])
            
            # Intrahepatic level: upper third of IVC (largest diameter typically)
            upper_third_start = len(slice_diameters) * 2 // 3
            upper_slices = slice_diameters[upper_third_start:]
            if upper_slices:
                intrahepatic = max(upper_slices, key=lambda x: x['diameter_mm'])
                intrahepatic_diameter = intrahepatic['diameter_mm']
            else:
                intrahepatic_diameter = max(s['diameter_mm'] for s in slice_diameters)
            
            # Infrarenal level: lower third of IVC
            lower_third_end = len(slice_diameters) // 3
            lower_slices = slice_diameters[:lower_third_end]
            if lower_slices:
                infrarenal = max(lower_slices, key=lambda x: x['diameter_mm'])
                infrarenal_diameter = infrarenal['diameter_mm']
            else:
                infrarenal_diameter = min(s['diameter_mm'] for s in slice_diameters)
            
            # Clinical classification based on intrahepatic diameter
            if intrahepatic_diameter < 15:
                classification = "Collapsed"
            elif intrahepatic_diameter > 25:
                classification = "Dilated"
            else:
                classification = "Normal"
            
            # IVC bounds for location verification (in physical coordinates)
            ivc_center = (ivc_min + ivc_max) / 2.0
            
            gt_data = {
                "case_id": case_id,
                "intrahepatic_diameter_mm": float(round(intrahepatic_diameter, 2)),
                "infrarenal_diameter_mm": float(round(infrarenal_diameter, 2)),
                "classification": classification,
                "spacing_mm": [float(s) for s in spacing],
                "ivc_bounds": {
                    "x_min": float(ivc_min[0] * spacing[0]),
                    "x_max": float(ivc_max[0] * spacing[0]),
                    "y_min": float(ivc_min[1] * spacing[1]),
                    "y_max": float(ivc_max[1] * spacing[1]),
                    "z_min": float(ivc_min[2] * spacing[2]),
                    "z_max": float(ivc_max[2] * spacing[2])
                },
                "total_ivc_slices": len(slice_diameters),
                "morphology": "Normal"
            }
            
            print(f"IVC Ground Truth:")
            print(f"  Intrahepatic diameter: {intrahepatic_diameter:.1f} mm")
            print(f"  Infrarenal diameter: {infrarenal_diameter:.1f} mm")
            print(f"  Classification: {classification}")

# Save ground truth
gt_path = os.path.join(gt_dir, f"{case_id}_ivc_gt.json")
with open(gt_path, 'w') as f:
    json.dump(gt_data, f, indent=2)
print(f"Ground truth saved to {gt_path}")
PYEOF

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${CASE_ID}_ivc_gt.json" ]; then
    echo "WARNING: IVC ground truth computation may have failed"
fi

# Create a Slicer Python script to load the CT with abdominal window
cat > /tmp/load_amos_ct_ivc.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
case_id = "$CASE_ID"

print(f"Loading AMOS CT scan for IVC assessment: {case_id}...")

volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("AbdominalCT")
    
    # Set standard abdominal window/level for soft tissue
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Soft tissue window good for visualizing IVC
        displayNode.SetWindow(400)
        displayNode.SetLevel(40)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Center on the data - focus on mid-abdomen where IVC is visible
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        center = [(bounds[i*2] + bounds[i*2+1])/2 for i in range(3)]
        if color == "Red":
            sliceNode.SetSliceOffset(center[2])
        elif color == "Green":
            sliceNode.SetSliceOffset(center[1])
        else:
            sliceNode.SetSliceOffset(center[0])
    
    print(f"CT loaded with abdominal soft tissue window (W=400, L=40)")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for IVC diameter assessment task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the CT data
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_amos_ct_ivc.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window for optimal agent interaction
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
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/ivc_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Inferior Vena Cava (IVC) Diameter Assessment"
echo "===================================================="
echo ""
echo "You are given an abdominal CT scan. Evaluate the IVC for volume status."
echo ""
echo "Your goals:"
echo "  1. Locate the IVC (large vein to the RIGHT of the aorta)"
echo "  2. Measure intrahepatic IVC diameter (upper level, below hepatic veins)"
echo "  3. Measure infrarenal IVC diameter (lower level, L3-L4)"
echo "  4. Classify: Normal (15-25mm), Dilated (>25mm), Collapsed (<15mm)"
echo ""
echo "Save your outputs:"
echo "  - Measurements: ~/Documents/SlicerData/AMOS/ivc_measurements.mrk.json"
echo "  - Report: ~/Documents/SlicerData/AMOS/ivc_report.json"
echo ""