#!/bin/bash
echo "=== Setting up Tumor-to-Vessel Distance Measurement Task ==="

source /workspace/scripts/task_utils.sh

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
PATIENT_NUM="5"  # Patient 5 has tumors and portal vein

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create necessary directories
mkdir -p "$IRCADB_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$EXPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Clean any previous task results
rm -f "$EXPORTS_DIR/tumor_vessel_distance.json" 2>/dev/null || true
rm -f /tmp/tvd_task_result.json 2>/dev/null || true

# Record initial state of exports directory
ls -la "$EXPORTS_DIR" > /tmp/initial_exports_list.txt 2>/dev/null || true

# Prepare IRCADb data (downloads real data if not exists)
echo "Preparing IRCADb liver CT data..."
export PATIENT_NUM GROUND_TRUTH_DIR IRCADB_DIR
/workspace/scripts/prepare_ircadb_data.sh "$PATIENT_NUM"

# Get the patient number actually used
if [ -f /tmp/ircadb_patient_num ]; then
    PATIENT_NUM=$(cat /tmp/ircadb_patient_num)
fi
echo "Using patient: $PATIENT_NUM"

PATIENT_DIR="$IRCADB_DIR/patient_${PATIENT_NUM}"
CT_FILE="$IRCADB_DIR/ircadb_patient${PATIENT_NUM}.nii.gz"
SEG_FILE="$IRCADB_DIR/ircadb_patient${PATIENT_NUM}_seg.nrrd"

# Check for patient data
if [ -d "$PATIENT_DIR/PATIENT_DICOM" ]; then
    DATA_SOURCE="DICOM"
    DATA_PATH="$PATIENT_DIR/PATIENT_DICOM"
    echo "Found DICOM data at: $DATA_PATH"
elif [ -f "$CT_FILE" ]; then
    DATA_SOURCE="NIfTI"
    DATA_PATH="$CT_FILE"
    echo "Found NIfTI data at: $DATA_PATH"
else
    echo "ERROR: Patient data not found"
    exit 1
fi

# Create segmentation file for Slicer if it doesn't exist
if [ ! -f "$SEG_FILE" ]; then
    echo "Creating segmentation file from labelmap..."
    python3 << PYEOF
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

gt_dir = "$GROUND_TRUTH_DIR"
patient_num = "$PATIENT_NUM"
output_seg = "$SEG_FILE"

# Load ground truth labelmap
gt_path = os.path.join(gt_dir, f"ircadb_patient{patient_num}_seg.nii.gz")
if not os.path.exists(gt_path):
    print(f"WARNING: Ground truth labelmap not found at {gt_path}")
    sys.exit(0)

gt_nii = nib.load(gt_path)
gt_data = gt_nii.get_fdata().astype(np.int16)

# Create a copy for Slicer (as NRRD)
# Labels: 1=liver, 2=tumor, 3=portal_vein
output_nii = nib.Nifti1Image(gt_data, gt_nii.affine, gt_nii.header)
output_path = output_seg.replace('.nrrd', '.nii.gz')
nib.save(output_nii, output_path)
print(f"Saved segmentation labelmap to {output_path}")

# Also save as NRRD for Slicer compatibility
try:
    import nrrd
    nrrd.write(output_seg, gt_data, header={'space': 'left-posterior-superior'})
    print(f"Saved as NRRD: {output_seg}")
except ImportError:
    print("nrrd module not available, using NIfTI format")
PYEOF
fi

# Verify ground truth exists
GT_JSON="$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_gt.json"
if [ ! -f "$GT_JSON" ]; then
    echo "ERROR: Ground truth JSON not found at $GT_JSON"
    echo "Available files in ground truth dir:"
    ls -la "$GROUND_TRUTH_DIR" 2>/dev/null || echo "Directory empty or missing"
    exit 1
fi

# Copy ground truth to accessible location for verification
cp "$GT_JSON" /tmp/tvd_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/tvd_ground_truth.json 2>/dev/null || true

echo "Ground truth file ready"

# Create a Slicer Python script to load data and set up visualization
LOAD_SCRIPT="/tmp/load_ircadb_data.py"
cat > "$LOAD_SCRIPT" << 'PYEOF'
import slicer
import os

# Paths
ircadb_dir = "/home/ga/Documents/SlicerData/IRCADb"
patient_num = os.environ.get("PATIENT_NUM", "5")

# Find data files
ct_nifti = os.path.join(ircadb_dir, f"ircadb_patient{patient_num}.nii.gz")
seg_nifti = os.path.join(ircadb_dir, f"ircadb_patient{patient_num}_seg.nii.gz")
dicom_dir = os.path.join(ircadb_dir, f"patient_{patient_num}", "PATIENT_DICOM")

# Load CT volume
volume_node = None
if os.path.exists(ct_nifti):
    print(f"Loading CT from NIfTI: {ct_nifti}")
    volume_node = slicer.util.loadVolume(ct_nifti)
elif os.path.exists(dicom_dir):
    print(f"Loading CT from DICOM: {dicom_dir}")
    from DICOMLib import DICOMUtils
    with DICOMUtils.TemporaryDICOMDatabase() as db:
        DICOMUtils.importDicom(dicom_dir, db)
        patientUIDs = db.patients()
        if patientUIDs:
            volume_node = DICOMUtils.loadPatientByUID(patientUIDs[0])

if volume_node:
    print(f"CT loaded: {volume_node.GetName()}")
else:
    print("WARNING: Could not load CT volume")

# Load segmentation
seg_node = None
if os.path.exists(seg_nifti):
    print(f"Loading segmentation from: {seg_nifti}")
    labelmap_node = slicer.util.loadLabelVolume(seg_nifti)
    
    # Convert labelmap to segmentation
    seg_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLSegmentationNode")
    seg_node.SetName("LiverSegmentation")
    slicer.modules.segmentations.logic().ImportLabelmapToSegmentationNode(labelmap_node, seg_node)
    
    # Remove the temporary labelmap
    slicer.mrmlScene.RemoveNode(labelmap_node)
    
    # Rename segments with meaningful names and set colors
    segmentation = seg_node.GetSegmentation()
    
    # Expected labels: 1=Liver, 2=Tumor, 3=PortalVein
    segment_info = {
        "1": ("Liver", (0.0, 0.8, 0.0)),      # Green
        "2": ("Tumor", (1.0, 0.0, 0.0)),      # Red
        "3": ("PortalVein", (0.0, 0.0, 1.0))  # Blue
    }
    
    for seg_id in range(segmentation.GetNumberOfSegments()):
        segment = segmentation.GetNthSegment(seg_id)
        seg_name = segment.GetName()
        
        # Try to match by label value in name
        for label_val, (name, color) in segment_info.items():
            if label_val in seg_name or name.lower() in seg_name.lower():
                segment.SetName(name)
                segment.SetColor(*color)
                print(f"  Renamed segment to: {name}")
                break
    
    # Make segmentation visible in 3D
    seg_node.CreateClosedSurfaceRepresentation()
    
    print("Segmentation loaded and configured")

# Set up 3D view
layoutManager = slicer.app.layoutManager()
layoutManager.setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

# Reset 3D view
threeDWidget = layoutManager.threeDWidget(0)
threeDView = threeDWidget.threeDView()
threeDView.resetFocalPoint()
threeDView.resetCamera()

# Set window/level for CT (abdominal soft tissue)
if volume_node:
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetAutoWindowLevel(False)
        displayNode.SetWindow(400)
        displayNode.SetLevel(50)

print("Setup complete - ready for measurement")
PYEOF

chmod 644 "$LOAD_SCRIPT"
chown ga:ga "$LOAD_SCRIPT"

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the data loading script
echo "Launching 3D Slicer with liver CT data..."
export PATIENT_NUM
su - ga -c "DISPLAY=:1 PATIENT_NUM=$PATIENT_NUM /opt/Slicer/Slicer --python-script $LOAD_SCRIPT > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start and load data
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 120

# Additional wait for data to load
echo "Waiting for data to load..."
sleep 15

# Maximize Slicer window
SLICER_WID=$(get_slicer_window_id)
if [ -n "$SLICER_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$SLICER_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$SLICER_WID" 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/tvd_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "DATA LOADED:"
echo "  - Liver CT scan from IRCADb patient $PATIENT_NUM"
echo "  - Segmentation with: Liver (green), Tumor (red), PortalVein (blue)"
echo ""
echo "YOUR TASK:"
echo "  1. Measure the minimum distance from Tumor to PortalVein"
echo "  2. Determine if safely resectable (distance >= 10mm)"
echo "  3. Save result to: ~/Documents/SlicerData/Exports/tumor_vessel_distance.json"
echo ""
echo "JSON format required:"
echo '  {"minimum_distance_mm": <number>, "safely_resectable": <true/false>}'
echo ""