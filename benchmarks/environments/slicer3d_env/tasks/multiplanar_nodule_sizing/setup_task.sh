#!/bin/bash
echo "=== Setting up Multi-planar Nodule Sizing Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

# Create directories
mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Clean any previous outputs
rm -f "$LIDC_DIR/multiplanar_measurements.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/nodule_sizing_report.json" 2>/dev/null || true
rm -f /tmp/multiplanar_task_result.json 2>/dev/null || true

# Prepare LIDC data
echo "Preparing LIDC-IDRI data..."
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID"

# Get the patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

echo "Using patient: $PATIENT_ID"

# Verify DICOM data exists
DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"
if [ ! -d "$DICOM_DIR" ]; then
    DICOM_DIR=$(find "$LIDC_DIR" -type d -name "DICOM" 2>/dev/null | head -1)
fi

if [ -z "$DICOM_DIR" ] || [ ! -d "$DICOM_DIR" ]; then
    echo "ERROR: DICOM directory not found!"
    exit 1
fi

DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
echo "Found $DICOM_COUNT DICOM files in $DICOM_DIR"

if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "ERROR: Too few DICOM files ($DICOM_COUNT)"
    exit 1
fi

# Create ground truth with multi-planar measurements if not exists
if [ ! -f "$GROUND_TRUTH_DIR/${PATIENT_ID}_multiplanar_gt.json" ]; then
    echo "Creating ground truth measurements..."
    
    python3 << PYEOF
import json
import os
import numpy as np

gt_dir = "$GROUND_TRUTH_DIR"
patient_id = "$PATIENT_ID"
lidc_dir = "$LIDC_DIR"

# Load existing nodule data
nodule_data = {}
gt_nodule_path = os.path.join(gt_dir, f"{patient_id}_nodules.json")
if os.path.exists(gt_nodule_path):
    with open(gt_nodule_path, 'r') as f:
        nodule_data = json.load(f)

nodules = nodule_data.get('nodules', [])

if nodules:
    nodule = nodules[0]
    # Get base diameter or generate realistic values
    base_diam = nodule.get('diameter_mm', 10.0)
    
    # Create realistic multi-planar dimensions
    # Simulate an elongated nodule for more interesting verification
    np.random.seed(42)
    
    # Generate dimensions that create an elongated shape
    # Axial tends to underestimate elongated nodules
    elongation_factor = 1.25 + np.random.uniform(0, 0.15)
    axial_factor = 0.85 + np.random.uniform(0, 0.1)
    
    axial_diam = round(base_diam * axial_factor, 1)
    coronal_diam = round(base_diam * elongation_factor, 1)
    sagittal_diam = round(base_diam * (1.0 + np.random.uniform(0, 0.2)), 1)
    
    max_diam = max(axial_diam, coronal_diam, sagittal_diam)
    min_diam = min(axial_diam, coronal_diam, sagittal_diam)
    asphericity = (max_diam - min_diam) / max_diam * 100 if max_diam > 0 else 0
    
    # Determine shape classification
    shape = "ELONGATED" if asphericity >= 25 else "SPHERICAL"
    
    # The preliminary report will have only axial
    preliminary_axial = axial_diam
    discrepant = abs(max_diam - preliminary_axial) > 2.0
    
    gt_multiplanar = {
        "patient_id": patient_id,
        "nodule_index": 0,
        "centroid_xyz": nodule.get('centroid_xyz', [0, 0, 0]),
        "axial_diameter_mm": axial_diam,
        "coronal_diameter_mm": coronal_diam,
        "sagittal_diameter_mm": sagittal_diam,
        "max_diameter_mm": max_diam,
        "min_diameter_mm": min_diam,
        "asphericity_percent": round(asphericity, 1),
        "shape_classification": shape,
        "preliminary_axial_mm": preliminary_axial,
        "discrepancy_flag": discrepant
    }
else:
    # Generate synthetic ground truth
    gt_multiplanar = {
        "patient_id": patient_id,
        "nodule_index": 0,
        "centroid_xyz": [256, 256, 100],
        "axial_diameter_mm": 9.5,
        "coronal_diameter_mm": 12.8,
        "sagittal_diameter_mm": 11.2,
        "max_diameter_mm": 12.8,
        "min_diameter_mm": 9.5,
        "asphericity_percent": 25.8,
        "shape_classification": "ELONGATED",
        "preliminary_axial_mm": 9.5,
        "discrepancy_flag": True
    }

# Save ground truth
gt_path = os.path.join(gt_dir, f"{patient_id}_multiplanar_gt.json")
with open(gt_path, 'w') as f:
    json.dump(gt_multiplanar, f, indent=2)
print(f"Ground truth saved to {gt_path}")

# Also copy to /tmp for verifier access
import shutil
shutil.copy(gt_path, "/tmp/multiplanar_ground_truth.json")
os.chmod("/tmp/multiplanar_ground_truth.json", 0o644)

print(f"Ground truth values:")
print(f"  Axial: {gt_multiplanar['axial_diameter_mm']} mm")
print(f"  Coronal: {gt_multiplanar['coronal_diameter_mm']} mm")
print(f"  Sagittal: {gt_multiplanar['sagittal_diameter_mm']} mm")
print(f"  Max: {gt_multiplanar['max_diameter_mm']} mm")
print(f"  Asphericity: {gt_multiplanar['asphericity_percent']}%")
print(f"  Shape: {gt_multiplanar['shape_classification']}")
print(f"  Discrepant: {gt_multiplanar['discrepancy_flag']}")
PYEOF
fi

# Create preliminary measurement report for agent
echo "Creating preliminary measurement report..."
python3 << PYEOF
import json
import os

gt_path = "/tmp/multiplanar_ground_truth.json"
prelim_path = "$LIDC_DIR/preliminary_measurement.json"

if os.path.exists(gt_path):
    with open(gt_path, 'r') as f:
        gt_data = json.load(f)
    
    preliminary = {
        "patient_id": gt_data.get("patient_id", "$PATIENT_ID"),
        "measurement_type": "AXIAL_ONLY",
        "nodule_location_xyz": gt_data.get("centroid_xyz", [256, 256, 100]),
        "axial_diameter_mm": gt_data.get("preliminary_axial_mm", 9.5),
        "measurement_date": "$(date +%Y-%m-%d)",
        "status": "REQUIRES_MULTIPLANAR_VERIFICATION",
        "note": "Initial axial-only measurement. Multi-planar verification required to confirm true maximum diameter. Navigate to nodule location and measure in axial, coronal, and sagittal planes."
    }
else:
    preliminary = {
        "patient_id": "$PATIENT_ID",
        "measurement_type": "AXIAL_ONLY",
        "nodule_location_xyz": [256, 256, 100],
        "axial_diameter_mm": 9.5,
        "measurement_date": "$(date +%Y-%m-%d)",
        "status": "REQUIRES_MULTIPLANAR_VERIFICATION",
        "note": "Initial axial-only measurement. Multi-planar verification required."
    }

with open(prelim_path, 'w') as f:
    json.dump(preliminary, f, indent=2)

print(f"Preliminary report created: {prelim_path}")
print(json.dumps(preliminary, indent=2))
PYEOF

# Set permissions
chown -R ga:ga "$LIDC_DIR" 2>/dev/null || true
chmod -R 755 "$LIDC_DIR" 2>/dev/null || true

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Create Slicer Python script to load DICOM
cat > /tmp/load_lidc_dicom.py << PYEOF
import slicer
import os

dicom_dir = "$DICOM_DIR"
patient_id = "$PATIENT_ID"

print(f"Loading LIDC chest CT for patient {patient_id}...")
print(f"DICOM directory: {dicom_dir}")

# Import DICOM
try:
    from DICOMLib import DICOMUtils
    
    # Add DICOM directory to database
    indexer = ctk.ctkDICOMIndexer()
    indexer.addDirectory(slicer.dicomDatabase, dicom_dir)
    
    # Get patient/study/series info
    patients = slicer.dicomDatabase.patients()
    if patients:
        patient = patients[0]
        studies = slicer.dicomDatabase.studiesForPatient(patient)
        if studies:
            study = studies[0]
            series_list = slicer.dicomDatabase.seriesForStudy(study)
            if series_list:
                # Load the first (usually main CT) series
                series = series_list[0]
                files = slicer.dicomDatabase.filesForSeries(series)
                print(f"Loading series with {len(files)} files...")
                
                loadedNodeIDs = DICOMUtils.loadSeriesByUID([series])
                if loadedNodeIDs:
                    volume_node = slicer.mrmlScene.GetNodeByID(loadedNodeIDs[0])
                    if volume_node:
                        volume_node.SetName("ChestCT")
                        print(f"Loaded volume: {volume_node.GetName()}")
                        print(f"Dimensions: {volume_node.GetImageData().GetDimensions()}")
                        
                        # Set lung window/level for nodule visualization
                        displayNode = volume_node.GetDisplayNode()
                        if displayNode:
                            displayNode.SetWindow(1500)
                            displayNode.SetLevel(-500)
                            displayNode.SetAutoWindowLevel(False)
                        
                        # Center views on volume
                        slicer.util.resetSliceViews()
except Exception as e:
    print(f"DICOM import error: {e}")
    print("Trying direct volume load...")
    
    # Fallback: look for any NIfTI files
    import glob
    nifti_files = glob.glob(os.path.join(os.path.dirname(dicom_dir), "*.nii*"))
    if nifti_files:
        volume_node = slicer.util.loadVolume(nifti_files[0])
        if volume_node:
            volume_node.SetName("ChestCT")
            displayNode = volume_node.GetDisplayNode()
            if displayNode:
                displayNode.SetWindow(1500)
                displayNode.SetLevel(-500)
            slicer.util.resetSliceViews()

print("Setup complete - ready for multi-planar nodule sizing task")
PYEOF

# Launch Slicer
echo "Launching 3D Slicer..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_lidc_dicom.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 15

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
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    
    # Re-focus
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/multiplanar_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Multi-planar Pulmonary Nodule Dimension Verification"
echo "============================================================"
echo ""
echo "A lung nodule was measured in the axial plane only."
echo "You must verify this measurement across ALL THREE planes."
echo ""
echo "Preliminary report: $LIDC_DIR/preliminary_measurement.json"
echo ""
echo "Your outputs:"
echo "  - Measurements: $LIDC_DIR/multiplanar_measurements.mrk.json"
echo "  - Report: $LIDC_DIR/nodule_sizing_report.json"
echo ""