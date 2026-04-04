#!/bin/bash
echo "=== Setting up Rib Counting and Vertebral Level Localization Task ==="

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

# Prepare LIDC data (downloads real data if not exists)
echo "Preparing LIDC-IDRI chest CT data..."
export PATIENT_ID GROUND_TRUTH_DIR LIDC_DIR
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID"

# Get the patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"

echo "Using patient: $PATIENT_ID"

# Verify DICOM files exist
DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
if [ "$DICOM_COUNT" -lt 50 ]; then
    echo "ERROR: Not enough DICOM files found ($DICOM_COUNT)"
    exit 1
fi
echo "Found $DICOM_COUNT DICOM files"

# Create ground truth for vertebral levels if not exists
if [ ! -f "$GROUND_TRUTH_DIR/${PATIENT_ID}_vertebral_gt.json" ]; then
    echo "Creating ground truth for vertebral levels..."
    python3 << 'PYEOF'
import os
import json
import glob

patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0001")
lidc_dir = os.environ.get("LIDC_DIR", "/home/ga/Documents/SlicerData/LIDC")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

# Load nodule info from preparation step
nodule_info_path = os.path.join(gt_dir, f"{patient_id}_nodules.json")
if os.path.exists(nodule_info_path):
    with open(nodule_info_path, 'r') as f:
        nodule_data = json.load(f)
else:
    # Default ground truth for LIDC-IDRI-0001
    nodule_data = {
        "patient_id": patient_id,
        "nodules": [
            {
                "centroid_xyz": [100.0, -150.0, -50.0],
                "diameter_pixels": 8.5,
                "reader_agreement": 3
            }
        ]
    }

# Define vertebral level ground truth based on typical chest CT anatomy
# For LIDC-IDRI-0001, the nodule is typically in the right upper lobe
# We'll assign vertebral levels based on Z-coordinate ranges
# Typical thoracic spine spans ~250mm (T1-T12)

# Estimate vertebral levels from image geometry
# Assume superior border of T1 is near carina level
# Each vertebral body is approximately 20-25mm in height

ground_truth = {
    "patient_id": patient_id,
    "total_rib_pairs": 12,
    "anatomical_variants": {
        "cervical_rib": False,
        "lumbar_rib": False,
        "bifid_rib": False,
        "bifid_rib_level": None
    },
    "vertebral_body_centers_approx": {
        "T1": {"z_offset_from_carina_mm": 0},
        "T6": {"z_offset_from_carina_mm": -120},
        "T12": {"z_offset_from_carina_mm": -250}
    },
    "t1_t12_expected_distance_mm": 250,
    "nodule_info": {}
}

# Determine nodule vertebral level
if nodule_data.get("nodules"):
    nodule = nodule_data["nodules"][0]
    centroid = nodule.get("centroid_xyz", [0, 0, 0])
    nodule_z = centroid[2] if len(centroid) > 2 else 0
    
    # For typical chest CT coordinate systems:
    # Higher Z (less negative) = more superior
    # We'll estimate based on typical lung anatomy
    # Most upper lobe nodules are T3-T6 level
    # Lower lobe nodules are T7-T12 level
    
    # This is a simplified heuristic - in real data we'd use
    # actual vertebral body positions from the CT
    if nodule_z > -50:
        nodule_level = "T4"
    elif nodule_z > -100:
        nodule_level = "T5"
    elif nodule_z > -150:
        nodule_level = "T6"
    elif nodule_z > -200:
        nodule_level = "T8"
    else:
        nodule_level = "T10"
    
    ground_truth["nodule_vertebral_level"] = nodule_level
    ground_truth["nodule_info"] = {
        "centroid_xyz": centroid,
        "z_coordinate": nodule_z
    }
else:
    # Default for synthetic/fallback case
    ground_truth["nodule_vertebral_level"] = "T5"
    ground_truth["nodule_info"] = {
        "centroid_xyz": [0, 0, -80],
        "z_coordinate": -80
    }

# Save ground truth
gt_path = os.path.join(gt_dir, f"{patient_id}_vertebral_gt.json")
with open(gt_path, 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(f"Nodule vertebral level: {ground_truth['nodule_vertebral_level']}")
PYEOF
fi

# Verify ground truth exists
if [ ! -f "$GROUND_TRUTH_DIR/${PATIENT_ID}_vertebral_gt.json" ]; then
    echo "ERROR: Ground truth not found!"
    exit 1
fi
echo "Ground truth verified (hidden from agent)"

# Read nodule position from ground truth
NODULE_POS=$(python3 -c "
import json
with open('$GROUND_TRUTH_DIR/${PATIENT_ID}_vertebral_gt.json') as f:
    gt = json.load(f)
pos = gt.get('nodule_info', {}).get('centroid_xyz', [0, 0, -80])
print(f'{pos[0]},{pos[1]},{pos[2]}')
" 2>/dev/null || echo "0,0,-80")

# Clean previous outputs
rm -f /tmp/rib_task_result.json 2>/dev/null || true
rm -f "$LIDC_DIR/vertebral_landmarks.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/rib_count_report.json" 2>/dev/null || true

# Create Slicer Python script to load DICOM and place nodule marker
cat > /tmp/load_lidc_ct.py << PYEOF
import slicer
import os
import DICOMLib

dicom_dir = "$DICOM_DIR"
patient_id = "$PATIENT_ID"
nodule_pos_str = "$NODULE_POS"

print(f"Loading chest CT for {patient_id}...")

# Parse nodule position
nodule_pos = [float(x) for x in nodule_pos_str.split(',')]
print(f"Nodule position: {nodule_pos}")

# Import DICOM data
print("Importing DICOM files...")
dicomBrowser = slicer.modules.dicom.widgetRepresentation().self().browserWidget
dicomBrowser.dicomBrowser.importDirectory(dicom_dir)
slicer.app.processEvents()

# Wait for indexing
import time
time.sleep(3)

# Get list of loadable items
db = slicer.dicomDatabase
patients = db.patients()
print(f"Found {len(patients)} patient(s) in database")

volume_node = None
for patient in patients:
    studies = db.studiesForPatient(patient)
    for study in studies:
        series_list = db.seriesForStudy(study)
        for series in series_list:
            files = db.filesForSeries(series)
            if len(files) > 10:  # CT series should have many slices
                print(f"Loading series with {len(files)} files...")
                loadables = DICOMLib.DICOMLoadableTable()
                plugins = slicer.modules.dicomPlugins
                for pluginName, pluginClass in plugins.items():
                    if 'Scalar' in pluginName or 'Volume' in pluginName:
                        try:
                            plugin = pluginClass()
                            pluginLoadables = plugin.examine([files])
                            if pluginLoadables:
                                # Load the first suitable loadable
                                volume_node = plugin.load(pluginLoadables[0])
                                if volume_node:
                                    print(f"Loaded volume: {volume_node.GetName()}")
                                    break
                        except Exception as e:
                            pass
                if volume_node:
                    break
        if volume_node:
            break
    if volume_node:
        break

# If DICOM loading failed, try direct file loading
if not volume_node:
    print("DICOM plugin load failed, trying direct load...")
    import glob
    dcm_files = glob.glob(os.path.join(dicom_dir, "**/*"), recursive=True)
    dcm_files = [f for f in dcm_files if os.path.isfile(f)]
    if dcm_files:
        try:
            volume_node = slicer.util.loadVolume(dcm_files[0])
        except:
            pass

if volume_node:
    volume_node.SetName("ChestCT")
    
    # Set lung window for viewing
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(1500)  # Lung window
        displayNode.SetLevel(-500)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    # Reset views
    slicer.util.resetSliceViews()
    
    # Create the nodule marker fiducial
    print("Creating nodule marker...")
    fidNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLMarkupsFiducialNode", "Nodule")
    fidNode.AddControlPoint(nodule_pos[0], nodule_pos[1], nodule_pos[2], "Nodule")
    
    # Make the fiducial visible and prominent
    fidDisplayNode = fidNode.GetDisplayNode()
    if fidDisplayNode:
        fidDisplayNode.SetSelectedColor(1, 0, 0)  # Red
        fidDisplayNode.SetGlyphScale(3.0)
        fidDisplayNode.SetTextScale(4.0)
    
    # Center view on nodule
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceLogic = sliceWidget.sliceLogic()
        sliceNode = sliceLogic.GetSliceNode()
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(nodule_pos[2])
        elif color == "Green":  # Coronal
            sliceNode.SetSliceOffset(nodule_pos[1])
        else:  # Sagittal
            sliceNode.SetSliceOffset(nodule_pos[0])
    
    print(f"CT loaded with lung window (W=1500, L=-500)")
    print(f"Nodule marker placed at {nodule_pos}")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for rib counting task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Ensure DICOM database directory exists
mkdir -p /home/ga/.config/NA-MIC/Slicer/DICOM

# Launch Slicer with the Python script
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_lidc_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 15

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
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    # Re-focus and ensure maximized
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Wait for volume and marker to fully load
sleep 5

# Take initial screenshot
take_screenshot /tmp/rib_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Rib Counting and Vertebral Level Localization"
echo "====================================================="
echo ""
echo "A chest CT is loaded with a fiducial marker on a lung nodule (red 'Nodule' marker)."
echo "A thoracic surgeon needs to know the exact vertebral level for surgical planning."
echo ""
echo "Your goals:"
echo "  1. Count ribs systematically from T1 to T12 (use coronal/sagittal views)"
echo "  2. Check for anatomical variants (cervical rib, lumbar rib, bifid rib)"
echo "  3. Determine the vertebral level of the marked nodule"
echo "  4. Place reference fiducials at T1, T6, and T12 vertebral body CENTERS"
echo "  5. Save a JSON report with your findings"
echo ""
echo "Tips:"
echo "  - First rib: short, broad, nearly horizontal (articulates with T1)"
echo "  - Use bone window (W=2000, L=500) to see vertebrae clearly"
echo "  - Track each rib posteriorly to its vertebral attachment"
echo ""
echo "Save outputs to:"
echo "  - Landmarks: ~/Documents/SlicerData/LIDC/vertebral_landmarks.mrk.json"
echo "  - Report: ~/Documents/SlicerData/LIDC/rib_count_report.json"
echo ""