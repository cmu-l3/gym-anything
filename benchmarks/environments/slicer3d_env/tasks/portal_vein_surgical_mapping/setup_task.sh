#!/bin/bash
echo "=== Setting up Portal Vein Surgical Mapping Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(date -Iseconds)"

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_NUM="5"

# Ensure directories exist
mkdir -p "$IRCADB_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Prepare IRCADb data (downloads real data or generates synthetic)
echo "Preparing liver CT data from IRCADb..."
export PATIENT_NUM GROUND_TRUTH_DIR IRCADB_DIR
/workspace/scripts/prepare_ircadb_data.sh "$PATIENT_NUM"

# Get patient number that was actually used
if [ -f /tmp/ircadb_patient_num ]; then
    PATIENT_NUM=$(cat /tmp/ircadb_patient_num)
fi

TARGET_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"

echo "Using patient: $PATIENT_NUM"

# Verify data exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "ERROR: IRCADb data not found at $TARGET_DIR"
    ls -la "$IRCADB_DIR"
    exit 1
fi

# Clean up any previous results
echo "Cleaning previous results..."
rm -f "$IRCADB_DIR/portal_landmarks.mrk.json" 2>/dev/null || true
rm -f "$IRCADB_DIR/surgical_planning_report.json" 2>/dev/null || true
rm -f /tmp/portal_mapping_result.json 2>/dev/null || true

# Compute portal vein landmarks from ground truth segmentation for verification
echo "Computing ground truth anatomical landmarks..."
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

try:
    from scipy.ndimage import center_of_mass, distance_transform_edt, label as scipy_label
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy.ndimage import center_of_mass, distance_transform_edt, label as scipy_label

patient_num = os.environ.get("PATIENT_NUM", "5")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
gt_seg_path = f"{gt_dir}/ircadb_patient{patient_num}_seg.nii.gz"
gt_json_path = f"{gt_dir}/ircadb_patient{patient_num}_gt.json"

print(f"Looking for ground truth at: {gt_seg_path}")

# Load existing ground truth JSON if it exists
if os.path.exists(gt_json_path):
    with open(gt_json_path, 'r') as f:
        gt_data = json.load(f)
    print(f"Loaded existing ground truth from {gt_json_path}")
else:
    gt_data = {}
    print("Creating new ground truth data")

# Load segmentation if it exists
if os.path.exists(gt_seg_path):
    print("Loading ground truth segmentation...")
    seg_nii = nib.load(gt_seg_path)
    seg_data = seg_nii.get_fdata().astype(np.int16)
    affine = seg_nii.affine
    spacing = seg_nii.header.get_zooms()[:3]
    
    print(f"Segmentation shape: {seg_data.shape}")
    print(f"Voxel spacing: {spacing}")
    print(f"Unique labels: {np.unique(seg_data)}")
    
    # Extract masks (labels: 1=liver, 2=tumor, 3=portal vein)
    liver_mask = (seg_data == 1) | (seg_data == 2)
    tumor_mask = (seg_data == 2)
    portal_mask = (seg_data == 3)
    
    print(f"Liver voxels: {np.sum(liver_mask)}")
    print(f"Tumor voxels: {np.sum(tumor_mask)}")
    print(f"Portal vein voxels: {np.sum(portal_mask)}")
    
    if np.any(portal_mask):
        # Find portal vein landmarks from segmentation
        portal_coords = np.argwhere(portal_mask)
        portal_centroid = portal_coords.mean(axis=0)
        
        # Find the bifurcation point - look for slice with maximum area spread
        z_coords = portal_coords[:, 2]
        unique_z = np.unique(z_coords)
        
        max_area = 0
        bifurcation_z = int(portal_centroid[2])
        
        for z in unique_z:
            slice_mask = portal_mask[:, :, int(z)]
            area = np.sum(slice_mask)
            if area > max_area:
                max_area = area
                bifurcation_z = int(z)
        
        # Get centroid at bifurcation level
        bif_slice = portal_mask[:, :, bifurcation_z]
        bif_coords = np.argwhere(bif_slice)
        
        if len(bif_coords) > 0:
            bif_centroid_2d = bif_coords.mean(axis=0)
            bifurcation_voxel = np.array([bif_centroid_2d[0], bif_centroid_2d[1], bifurcation_z])
        else:
            bifurcation_voxel = portal_centroid.copy()
        
        # Convert to world coordinates (mm)
        bifurcation_world = [float(x * s) for x, s in zip(bifurcation_voxel, spacing)]
        
        # Estimate RPV and LPV origins (left/right of bifurcation)
        rpv_voxel = bifurcation_voxel.copy()
        rpv_voxel[0] -= 15  # Shift right (lower x)
        rpv_voxel[2] += 5   # Slightly superior
        
        lpv_voxel = bifurcation_voxel.copy()
        lpv_voxel[0] += 15  # Shift left (higher x)
        lpv_voxel[2] += 5   # Slightly superior
        
        mpv_voxel = bifurcation_voxel.copy()
        mpv_voxel[2] -= 10  # Inferior to bifurcation
        
        # Calculate portal vein diameter at bifurcation (equivalent diameter from area)
        bif_area_voxels = np.sum(bif_slice)
        bif_area_mm2 = bif_area_voxels * spacing[0] * spacing[1]
        pv_diameter_mm = 2 * np.sqrt(bif_area_mm2 / np.pi) if bif_area_mm2 > 0 else 12.0
        
        gt_data['portal_landmarks'] = {
            'bifurcation': bifurcation_world,
            'rpv_origin': [float(x * s) for x, s in zip(rpv_voxel, spacing)],
            'lpv_origin': [float(x * s) for x, s in zip(lpv_voxel, spacing)],
            'mpv_proximal': [float(x * s) for x, s in zip(mpv_voxel, spacing)],
            'portal_vein_diameter_mm': float(pv_diameter_mm),
            'estimated': False
        }
        
        print(f"Portal vein bifurcation at: {bifurcation_world}")
        print(f"Portal vein diameter: {pv_diameter_mm:.1f} mm")
    else:
        print("WARNING: No portal vein segmentation found, using estimated landmarks")
        # Create estimated landmarks based on liver centroid
        if np.any(liver_mask):
            liver_coords = np.argwhere(liver_mask)
            liver_centroid = liver_coords.mean(axis=0)
            
            # Portal vein is typically posterior-medial in liver
            bifurcation_voxel = liver_centroid.copy()
            bifurcation_voxel[1] += 30  # More posterior
            
            gt_data['portal_landmarks'] = {
                'bifurcation': [float(x * s) for x, s in zip(bifurcation_voxel, spacing)],
                'portal_vein_diameter_mm': 12.0,
                'estimated': True
            }
    
    # Calculate tumor-vessel distance
    if np.any(portal_mask) and np.any(tumor_mask):
        print("Computing tumor-vessel distance...")
        portal_dt = distance_transform_edt(~portal_mask, sampling=spacing)
        
        tumor_coords = np.argwhere(tumor_mask)
        min_dist = float('inf')
        
        for coord in tumor_coords[:1000]:  # Sample for speed
            dist = portal_dt[coord[0], coord[1], coord[2]]
            if dist < min_dist:
                min_dist = dist
        
        gt_data['tumor_vessel_distance_mm'] = float(min_dist)
        
        # Classify relationship
        if min_dist > 10:
            gt_data['tumor_vessel_relationship'] = 'Clear'
            gt_data['resectability'] = 'Resectable'
        elif min_dist > 5:
            gt_data['tumor_vessel_relationship'] = 'Close'
            gt_data['resectability'] = 'Resectable'
        elif min_dist > 1:
            gt_data['tumor_vessel_relationship'] = 'Abutting'
            gt_data['resectability'] = 'Potentially Resectable'
        else:
            gt_data['tumor_vessel_relationship'] = 'Involved'
            gt_data['resectability'] = 'Likely Unresectable'
        
        print(f"Tumor-vessel distance: {min_dist:.1f} mm")
        print(f"Relationship: {gt_data['tumor_vessel_relationship']}")
    else:
        gt_data['tumor_vessel_distance_mm'] = 15.0
        gt_data['tumor_vessel_relationship'] = 'Clear'
        gt_data['resectability'] = 'Resectable'
        print("Using default tumor-vessel relationship (Clear)")
else:
    print(f"WARNING: Ground truth segmentation not found at {gt_seg_path}")
    # Set default values
    gt_data['portal_landmarks'] = {
        'bifurcation': [100.0, 100.0, 100.0],
        'portal_vein_diameter_mm': 12.0,
        'estimated': True
    }
    gt_data['tumor_vessel_distance_mm'] = 15.0
    gt_data['tumor_vessel_relationship'] = 'Clear'
    gt_data['resectability'] = 'Resectable'

# Save ground truth
with open(gt_json_path, 'w') as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved to {gt_json_path}")
PYEOF

# Find the CT data to load
CT_FILE=""
if [ -d "$TARGET_DIR/PATIENT_DICOM" ] && [ "$(ls -A "$TARGET_DIR/PATIENT_DICOM" 2>/dev/null | head -1)" ]; then
    CT_FILE="$TARGET_DIR/PATIENT_DICOM"
    echo "Found DICOM directory: $CT_FILE"
elif [ -f "$TARGET_DIR/ct_volume.nii.gz" ]; then
    CT_FILE="$TARGET_DIR/ct_volume.nii.gz"
    echo "Found NIfTI volume: $CT_FILE"
elif [ -f "$IRCADB_DIR/patient_${PATIENT_NUM}.nii.gz" ]; then
    CT_FILE="$IRCADB_DIR/patient_${PATIENT_NUM}.nii.gz"
    echo "Found patient NIfTI: $CT_FILE"
fi

if [ -z "$CT_FILE" ] || [ ! -e "$CT_FILE" ]; then
    echo "ERROR: Could not find CT data"
    ls -la "$TARGET_DIR" 2>/dev/null || true
    ls -la "$IRCADB_DIR" 2>/dev/null || true
    exit 1
fi

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Slicer loading script
cat > /tmp/load_liver_ct.py << PYEOF
import slicer
import os

ct_path = "$CT_FILE"
patient_num = "$PATIENT_NUM"

print(f"Loading liver CT for patient {patient_num}...")

# Load volume
if os.path.isdir(ct_path):
    # DICOM directory
    from DICOMLib import DICOMUtils
    loadedNodeIDs = []
    with DICOMUtils.TemporaryDICOMDatabase() as db:
        DICOMUtils.importDicom(ct_path, db)
        patientUIDs = db.patients()
        for patient in patientUIDs:
            studies = db.studiesForPatient(patient)
            for study in studies:
                series = db.seriesForStudy(study)
                for serie in series:
                    loadedNodeIDs.extend(DICOMUtils.loadSeriesByUID([serie]))
    if loadedNodeIDs:
        volume_node = slicer.mrmlScene.GetNodeByID(loadedNodeIDs[0])
    else:
        volume_node = None
else:
    # NIfTI file
    volume_node = slicer.util.loadVolume(ct_path)

if volume_node:
    volume_node.SetName("LiverCT")
    
    # Set up abdominal CT window/level for vessel visualization
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        # Soft tissue window optimized for portal vein
        displayNode.SetWindow(350)
        displayNode.SetLevel(50)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset views
    slicer.util.resetSliceViews()
    
    # Center on liver region (approximate)
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
    
    print(f"Liver CT loaded successfully")
    print(f"Volume dimensions: {volume_node.GetImageData().GetDimensions()}")
    print(f"Window/Level set for portal vein visualization (W=350, L=50)")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for portal vein mapping task")
PYEOF

# Launch Slicer with the loading script
echo "Launching 3D Slicer with liver CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_liver_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 10

# Configure window
echo "Configuring Slicer window..."
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    
    # Maximize window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

# Save patient number for export script
echo "$PATIENT_NUM" > /tmp/ircadb_patient_num

echo ""
echo "=== Portal Vein Surgical Mapping Task Setup Complete ==="
echo ""
echo "Patient: $PATIENT_NUM"
echo "CT data: $CT_FILE"
echo ""
echo "TASK: Map portal vein anatomy for hepatic resection planning"
echo "================================================================"
echo ""
echo "Instructions:"
echo "  1. Identify the main portal vein (bright vessel entering liver)"
echo "  2. Locate the bifurcation where it splits into left/right branches"
echo "  3. Place fiducial markers at: Bifurcation, RPV, LPV, MPV"
echo "  4. Measure portal vein diameter using ruler tool"
echo "  5. Measure tumor-vessel distance"
echo "  6. Classify relationship: Clear/Close/Abutting/Involved"
echo ""
echo "Save outputs to:"
echo "  - Landmarks: ~/Documents/SlicerData/IRCADb/portal_landmarks.mrk.json"
echo "  - Report: ~/Documents/SlicerData/IRCADb/surgical_planning_report.json"
echo ""