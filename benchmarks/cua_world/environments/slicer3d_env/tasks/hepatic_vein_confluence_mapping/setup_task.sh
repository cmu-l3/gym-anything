#!/bin/bash
echo "=== Setting up Hepatic Vein Confluence Mapping Task ==="

source /workspace/scripts/task_utils.sh

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
PATIENT_NUM="5"  # Patient 5 has good hepatic vein visibility

# Create directories
mkdir -p "$IRCADB_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$SCREENSHOT_DIR"

# Prepare IRCADb data
echo "Preparing 3D-IRCADb liver CT data..."
export PATIENT_NUM GROUND_TRUTH_DIR
/workspace/scripts/prepare_ircadb_data.sh "$PATIENT_NUM"

# Get the patient number used
if [ -f /tmp/ircadb_patient_num ]; then
    PATIENT_NUM=$(cat /tmp/ircadb_patient_num)
fi

PATIENT_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"
echo "Using patient: $PATIENT_NUM"

# Find the CT volume
CT_FILE=""
if [ -f "$PATIENT_DIR/ct_volume.nii.gz" ]; then
    CT_FILE="$PATIENT_DIR/ct_volume.nii.gz"
elif [ -d "$PATIENT_DIR/PATIENT_DICOM" ]; then
    CT_FILE="$PATIENT_DIR/PATIENT_DICOM"
fi

if [ -z "$CT_FILE" ] || [ ! -e "$CT_FILE" ]; then
    echo "ERROR: CT data not found for patient $PATIENT_NUM"
    ls -la "$PATIENT_DIR" 2>/dev/null || echo "Patient directory not found"
    exit 1
fi
echo "CT data found: $CT_FILE"

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_gt.json" ]; then
    echo "WARNING: Ground truth JSON not found, creating from segmentation..."
    # Create ground truth from hepatic vein segmentation if available
    python3 << PYEOF
import json
import os
import numpy as np

gt_dir = "$GROUND_TRUTH_DIR"
patient_num = "$PATIENT_NUM"
seg_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_seg.nii.gz")

gt_data = {
    "patient_id": f"IRCADb_patient_{patient_num}",
    "hepatic_veins": {
        "rhv": {"expected_region": "right_posterior", "label": 3},
        "mhv": {"expected_region": "central", "label": 3},
        "lhv": {"expected_region": "left", "label": 3}
    },
    "ivc_region": {
        "z_range_superior": True,
        "description": "Superior liver near diaphragm"
    },
    "anatomical_pattern": "Type I (normal)",
    "notes": "Hepatic veins drain into IVC at hepatocaval confluence"
}

# If segmentation exists, try to extract vein positions
if os.path.exists(seg_path):
    try:
        import nibabel as nib
        seg = nib.load(seg_path)
        data = seg.get_fdata()
        affine = seg.affine
        
        # Portal vein label is typically 3 in IRCADb
        # Hepatic veins may be included or separate
        vein_mask = (data == 3)
        if np.any(vein_mask):
            coords = np.argwhere(vein_mask)
            # Find superior-most vein region (near IVC confluence)
            z_coords = coords[:, 2]
            superior_threshold = np.percentile(z_coords, 90)
            superior_coords = coords[z_coords >= superior_threshold]
            
            if len(superior_coords) > 0:
                # Estimate RAS coordinates
                center = superior_coords.mean(axis=0)
                ras = affine @ np.array([center[0], center[1], center[2], 1])
                gt_data["ivc_confluence_ras"] = ras[:3].tolist()
                gt_data["superior_liver_z"] = float(superior_threshold)
    except Exception as e:
        print(f"Could not process segmentation: {e}")

gt_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)
print(f"Ground truth saved to {gt_path}")
PYEOF
fi

# Record initial state
date +%s > /tmp/task_start_time.txt
echo "$PATIENT_NUM" > /tmp/ircadb_patient_num

# Clean up any previous task outputs
rm -f "$IRCADB_DIR/hepatic_vein_markups.mrk.json" 2>/dev/null || true
rm -f "$IRCADB_DIR/hepatic_vein_report.json" 2>/dev/null || true
rm -f "$SCREENSHOT_DIR/hepatic_confluence.png" 2>/dev/null || true
rm -f /tmp/hepatic_vein_task_result.json 2>/dev/null || true

# Create Slicer Python script to load CT and configure views
cat > /tmp/load_ircadb_ct.py << 'PYEOF'
import slicer
import os
import glob

patient_dir = os.environ.get("PATIENT_DIR", "/home/ga/Documents/SlicerData/IRCADb/patient_5")
patient_num = os.environ.get("PATIENT_NUM", "5")

print(f"Loading IRCADb patient {patient_num} CT scan...")

# Try to load from DICOM directory first
dicom_dir = os.path.join(patient_dir, "PATIENT_DICOM")
ct_nifti = os.path.join(patient_dir, "ct_volume.nii.gz")

volume_node = None

if os.path.isdir(dicom_dir) and len(os.listdir(dicom_dir)) > 0:
    print(f"Loading from DICOM directory: {dicom_dir}")
    # Import DICOM
    dicom_files = []
    for root, dirs, files in os.walk(dicom_dir):
        for f in files:
            dicom_files.append(os.path.join(root, f))
    
    if dicom_files:
        from DICOMLib import DICOMUtils
        loadedNodeIDs = []
        with DICOMUtils.TemporaryDICOMDatabase() as db:
            DICOMUtils.importDicom(dicom_dir, db)
            patientUIDs = db.patients()
            for patientUID in patientUIDs:
                loadedNodeIDs.extend(DICOMUtils.loadPatientByUID(patientUID))
        
        if loadedNodeIDs:
            volume_node = slicer.mrmlScene.GetNodeByID(loadedNodeIDs[0])

elif os.path.exists(ct_nifti):
    print(f"Loading from NIfTI: {ct_nifti}")
    volume_node = slicer.util.loadVolume(ct_nifti)

if volume_node:
    volume_node.SetName(f"LiverCT_Patient{patient_num}")
    
    # Set contrast-enhanced liver window/level
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Soft tissue window optimized for liver/vessels
        displayNode.SetWindow(350)
        displayNode.SetLevel(50)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all slice views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Navigate to superior liver (hepatic vein confluence region)
    bounds = [0]*6
    volume_node.GetBounds(bounds)
    
    # Hepatic veins are in the superior liver, near the diaphragm
    # Navigate to approximately 80% of the z-range (superior)
    z_min, z_max = bounds[4], bounds[5]
    superior_z = z_min + 0.8 * (z_max - z_min)
    
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        
        center_x = (bounds[0] + bounds[1]) / 2
        center_y = (bounds[2] + bounds[3]) / 2
        
        if color == "Red":  # Axial - navigate to superior liver
            sliceNode.SetSliceOffset(superior_z)
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(center_y)
        else:  # Sagittal
            sliceNode.SetSliceOffset(center_x)
    
    slicer.util.resetSliceViews()
    
    print(f"CT loaded: {volume_node.GetName()}")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Navigated to superior liver region (z={superior_z:.1f})")
    print("")
    print("Ready for hepatic vein confluence mapping task")
else:
    print("WARNING: Could not load CT volume")
    print(f"Checked: {dicom_dir}, {ct_nifti}")
PYEOF

# Export environment variables for Python script
export PATIENT_DIR="$PATIENT_DIR"
export PATIENT_NUM="$PATIENT_NUM"

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the Python script
echo "Launching 3D Slicer with liver CT..."
sudo -u ga DISPLAY=:1 PATIENT_DIR="$PATIENT_DIR" PATIENT_NUM="$PATIENT_NUM" \
    /opt/Slicer/Slicer --python-script /tmp/load_ircadb_ct.py > /tmp/slicer_launch.log 2>&1 &

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
fi

# Wait for volume to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/hepatic_vein_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Hepatic Vein Confluence Mapping"
echo "======================================="
echo ""
echo "You are given a contrast-enhanced liver CT scan for surgical planning."
echo ""
echo "Your goal:"
echo "  1. Navigate to the superior liver near the diaphragm"
echo "  2. Identify the Inferior Vena Cava (IVC)"
echo "  3. Locate and mark the three major hepatic veins:"
echo "     - Right Hepatic Vein (RHV) - most rightward"
echo "     - Middle Hepatic Vein (MHV) - central"
echo "     - Left Hepatic Vein (LHV) - most leftward"
echo "  4. Place fiducial markers at each vein's IVC entry point"
echo "  5. Label markers appropriately (RHV, MHV, LHV)"
echo "  6. Measure inter-vein distances"
echo "  7. Document the anatomical pattern"
echo "  8. Save screenshot and create JSON report"
echo ""
echo "Save outputs to:"
echo "  - Markups: ~/Documents/SlicerData/IRCADb/hepatic_vein_markups.mrk.json"
echo "  - Screenshot: ~/Documents/SlicerData/Screenshots/hepatic_confluence.png"
echo "  - Report: ~/Documents/SlicerData/IRCADb/hepatic_vein_report.json"
echo ""