#!/bin/bash
echo "=== Setting up Liver Steatosis Assessment Task ==="

source /workspace/scripts/task_utils.sh

STEATOSIS_DIR="/home/ga/Documents/SlicerData/Steatosis"
AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="steatosis_case"

# Create directories
mkdir -p "$STEATOSIS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga "$STEATOSIS_DIR" 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Clean up any previous task artifacts
rm -f "$STEATOSIS_DIR/liver_roi.mrk.json" 2>/dev/null || true
rm -f "$STEATOSIS_DIR/spleen_roi.mrk.json" 2>/dev/null || true
rm -f "$STEATOSIS_DIR/steatosis_report.json" 2>/dev/null || true
rm -f /tmp/steatosis_task_result.json 2>/dev/null || true

# Prepare AMOS data if not already done
echo "Preparing abdominal CT data..."
export CASE_ID GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID" 2>/dev/null || true

# Check if data exists, use alternative case ID if needed
if [ ! -f "$AMOS_DIR/${CASE_ID}.nii.gz" ]; then
    if [ -f "$AMOS_DIR/amos_0001.nii.gz" ]; then
        CASE_ID="amos_0001"
        echo "Using fallback case: $CASE_ID"
    fi
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"
echo "$CASE_ID" > /tmp/steatosis_case_id.txt

# Verify CT file exists
if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT volume not found at $CT_FILE"
    echo "Creating synthetic abdominal CT with known values..."
    
    # Create synthetic CT with known liver and spleen HU values
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

amos_dir = "/home/ga/Documents/SlicerData/AMOS"
gt_dir = "/var/lib/slicer/ground_truth"
os.makedirs(amos_dir, exist_ok=True)
os.makedirs(gt_dir, exist_ok=True)

np.random.seed(42)

# Volume dimensions (smaller for speed)
nx, ny, nz = 256, 256, 100
spacing = (0.78125, 0.78125, 2.5)

# Create affine
affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Initialize with soft tissue
ct_data = np.random.normal(40, 10, (nx, ny, nz)).astype(np.int16)

# Body outline
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2
body_mask = ((X - center_x)**2 / (100**2) + (Y - center_y)**2 / (80**2)) <= 1.0

# Air outside body
for z in range(nz):
    ct_data[:, :, z][~body_mask] = -1000

# LIVER: right side, HU ~58 (normal liver)
liver_cx, liver_cy = center_x - 35, center_y - 10
liver_mask = np.zeros((nx, ny, nz), dtype=bool)
for z in range(20, 85):
    liver_slice = ((X - liver_cx)**2 / (45**2) + (Y - liver_cy)**2 / (40**2)) <= 1.0
    liver_mask[:, :, z] = liver_slice & body_mask
    ct_data[:, :, z][liver_slice & body_mask] = np.random.normal(58, 8, np.sum(liver_slice & body_mask)).astype(np.int16)

# SPLEEN: left side, HU ~52 (normal spleen)
spleen_cx, spleen_cy = center_x + 55, center_y + 15
spleen_mask = np.zeros((nx, ny, nz), dtype=bool)
for z in range(35, 70):
    spleen_slice = ((X - spleen_cx)**2 + (Y - spleen_cy)**2) <= 22**2
    spleen_mask[:, :, z] = spleen_slice & body_mask
    ct_data[:, :, z][spleen_slice & body_mask] = np.random.normal(52, 6, np.sum(spleen_slice & body_mask)).astype(np.int16)

# Spine
spine_cx, spine_cy = center_x, center_y + 55
for z in range(nz):
    spine_mask = ((X - spine_cx)**2 + (Y - spine_cy)**2) <= 12**2
    ct_data[:, :, z][spine_mask] = np.random.normal(400, 60, np.sum(spine_mask)).astype(np.int16)

# Aorta
aorta_cx, aorta_cy = center_x, center_y + 30
for z in range(nz):
    aorta_mask = ((X - aorta_cx)**2 + (Y - aorta_cy)**2) <= 10**2
    ct_data[:, :, z][aorta_mask & body_mask] = np.random.normal(45, 10, np.sum(aorta_mask & body_mask)).astype(np.int16)

# Save CT
ct_nii = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(amos_dir, "steatosis_case.nii.gz")
nib.save(ct_nii, ct_path)
print(f"CT saved: {ct_path}")

# Save label map for ground truth
labels = np.zeros((nx, ny, nz), dtype=np.int16)
labels[liver_mask] = 6   # Liver
labels[spleen_mask] = 1  # Spleen

label_nii = nib.Nifti1Image(labels, affine)
label_path = os.path.join(gt_dir, "steatosis_case_labels.nii.gz")
nib.save(label_nii, label_path)
print(f"Labels saved: {label_path}")

# Calculate and save ground truth measurements
liver_hu = float(np.mean(ct_data[liver_mask]))
spleen_hu = float(np.mean(ct_data[spleen_mask]))
ls_ratio = liver_hu / spleen_hu if spleen_hu != 0 else 1.0

# Determine classification
if ls_ratio >= 1.0 and liver_hu >= 40:
    classification = "none"
elif ls_ratio >= 0.8 or liver_hu >= 30:
    classification = "mild"
elif ls_ratio >= 0.5 or liver_hu >= 10:
    classification = "moderate"
else:
    classification = "severe"

gt = {
    "liver_hu": round(liver_hu, 1),
    "spleen_hu": round(spleen_hu, 1),
    "ls_ratio": round(ls_ratio, 3),
    "classification": classification,
    "liver_voxels": int(np.sum(liver_mask)),
    "spleen_voxels": int(np.sum(spleen_mask)),
    "liver_center_voxel": [int(liver_cx), int(liver_cy), 50],
    "spleen_center_voxel": [int(spleen_cx), int(spleen_cy), 50],
    "voxel_spacing_mm": list(spacing)
}

gt_path = os.path.join(gt_dir, "steatosis_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground truth saved: {gt_path}")
print(f"  Liver HU: {liver_hu:.1f}")
print(f"  Spleen HU: {spleen_hu:.1f}")
print(f"  L/S Ratio: {ls_ratio:.3f}")
print(f"  Classification: {classification}")
PYEOF

    CT_FILE="$AMOS_DIR/steatosis_case.nii.gz"
    CASE_ID="steatosis_case"
    echo "$CASE_ID" > /tmp/steatosis_case_id.txt
fi

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/steatosis_gt.json" ]; then
    echo "Creating ground truth from existing CT..."
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

# Try to load CT and compute stats from label map
amos_dir = "/home/ga/Documents/SlicerData/AMOS"
gt_dir = "/var/lib/slicer/ground_truth"

case_id = open("/tmp/steatosis_case_id.txt").read().strip()
ct_path = os.path.join(amos_dir, f"{case_id}.nii.gz")
label_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")

if os.path.exists(ct_path) and os.path.exists(label_path):
    ct = nib.load(ct_path).get_fdata()
    labels = nib.load(label_path).get_fdata()
    
    liver_mask = (labels == 6)
    spleen_mask = (labels == 1)
    
    if np.any(liver_mask) and np.any(spleen_mask):
        liver_hu = float(np.mean(ct[liver_mask]))
        spleen_hu = float(np.mean(ct[spleen_mask]))
        ls_ratio = liver_hu / spleen_hu if spleen_hu != 0 else 1.0
        
        if ls_ratio >= 1.0 and liver_hu >= 40:
            classification = "none"
        elif ls_ratio >= 0.8 or liver_hu >= 30:
            classification = "mild"
        elif ls_ratio >= 0.5 or liver_hu >= 10:
            classification = "moderate"
        else:
            classification = "severe"
        
        gt = {
            "liver_hu": round(liver_hu, 1),
            "spleen_hu": round(spleen_hu, 1),
            "ls_ratio": round(ls_ratio, 3),
            "classification": classification
        }
        
        gt_path = os.path.join(gt_dir, "steatosis_gt.json")
        with open(gt_path, "w") as f:
            json.dump(gt, f, indent=2)
        print(f"Ground truth created: {gt}")
    else:
        # Use default values for synthetic normal case
        gt = {"liver_hu": 58.0, "spleen_hu": 52.0, "ls_ratio": 1.115, "classification": "none"}
        with open(os.path.join(gt_dir, "steatosis_gt.json"), "w") as f:
            json.dump(gt, f, indent=2)
        print("Using default ground truth values")
else:
    # Default values
    gt = {"liver_hu": 58.0, "spleen_hu": 52.0, "ls_ratio": 1.115, "classification": "none"}
    os.makedirs(gt_dir, exist_ok=True)
    with open(os.path.join(gt_dir, "steatosis_gt.json"), "w") as f:
        json.dump(gt, f, indent=2)
    print("Using default ground truth values")
PYEOF
fi

echo "CT volume: $CT_FILE"
echo "Case ID: $CASE_ID"

# Link CT to task directory
ln -sf "$CT_FILE" "$STEATOSIS_DIR/abdominal_ct.nii.gz" 2>/dev/null || cp "$CT_FILE" "$STEATOSIS_DIR/abdominal_ct.nii.gz"

# Create Slicer Python script to load CT
cat > /tmp/load_steatosis_ct.py << 'PYEOF'
import slicer
import os

ct_path = "/home/ga/Documents/SlicerData/Steatosis/abdominal_ct.nii.gz"

print("Loading abdominal CT for steatosis assessment...")

if os.path.exists(ct_path):
    volume_node = slicer.util.loadVolume(ct_path)
    
    if volume_node:
        volume_node.SetName("AbdominalCT")
        
        # Set soft tissue window (good for liver/spleen)
        displayNode = volume_node.GetDisplayNode()
        if displayNode:
            displayNode.SetWindow(350)
            displayNode.SetLevel(40)
            displayNode.SetAutoWindowLevel(False)
        
        # Set as background in all views
        for color in ["Red", "Green", "Yellow"]:
            sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
            sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
        
        slicer.util.resetSliceViews()
        
        # Center views on data
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
        
        print(f"CT loaded with soft tissue window (W=350, L=40)")
        print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    else:
        print("ERROR: Could not load CT volume")
else:
    print(f"ERROR: CT file not found at {ct_path}")

print("Setup complete - ready for steatosis assessment")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with abdominal CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_steatosis_ct.py > /tmp/slicer_launch.log 2>&1 &

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
    
    # Maximize
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 3

# Take initial screenshot
take_screenshot /tmp/steatosis_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Liver Steatosis (Fatty Liver) Assessment"
echo "==============================================="
echo ""
echo "You have an abdominal CT scan loaded. Assess for hepatic steatosis by:"
echo ""
echo "1. Navigate to the LIVER (right upper abdomen)"
echo "   - Place a fiducial/ROI in homogeneous liver parenchyma"
echo "   - Avoid vessels and lesions"
echo "   - Save to: ~/Documents/SlicerData/Steatosis/liver_roi.mrk.json"
echo ""
echo "2. Navigate to the SPLEEN (left upper abdomen)"  
echo "   - Place a fiducial/ROI in splenic parenchyma"
echo "   - Save to: ~/Documents/SlicerData/Steatosis/spleen_roi.mrk.json"
echo ""
echo "3. Measure mean HU values and calculate L/S ratio"
echo ""
echo "4. Create a report at: ~/Documents/SlicerData/Steatosis/steatosis_report.json"
echo "   Required fields: liver_hu, spleen_hu, ls_ratio, classification"
echo ""
echo "Classification:"
echo "  - None/Normal: L/S >= 1.0 AND liver >= 40 HU"
echo "  - Mild: L/S 0.8-1.0 OR liver 30-40 HU"
echo "  - Moderate: L/S 0.5-0.8 OR liver 10-30 HU"
echo "  - Severe: L/S < 0.5 OR liver < 10 HU"
echo ""