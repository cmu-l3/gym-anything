#!/bin/bash
echo "=== Setting up Lung Nodule Measurement Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

mkdir -p "$LIDC_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Prepare LIDC data (downloads real data if not exists)
echo "Preparing LIDC-IDRI data..."
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
if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "ERROR: Insufficient DICOM files found at $DICOM_DIR"
    echo "Attempting to create synthetic lung CT data..."
    
    # Create synthetic lung CT with nodule if real data unavailable
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

lidc_dir = os.environ.get("LIDC_DIR", "/home/ga/Documents/SlicerData/LIDC")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0001")

np.random.seed(42)

# Create synthetic chest CT with a lung nodule
nx, ny, nz = 256, 256, 150
spacing = (0.7, 0.7, 2.5)  # mm per voxel

affine = np.eye(4)
affine[0, 0] = spacing[0]
affine[1, 1] = spacing[1]
affine[2, 2] = spacing[2]

# Initialize with air (-1000 HU)
ct_data = np.full((nx, ny, nz), -1000, dtype=np.int16)

# Create body outline (ellipse)
Y, X = np.ogrid[:nx, :ny]
center_x, center_y = nx // 2, ny // 2

# Body mask
body_a, body_b = 100, 80
body_mask = ((X - center_x)**2 / body_a**2 + (Y - center_y)**2 / body_b**2) <= 1.0

# Lung masks (two ellipses)
lung_a, lung_b = 40, 55
lung_left_cx = center_x + 45
lung_right_cx = center_x - 45
lung_cy = center_y - 10

left_lung = ((X - lung_left_cx)**2 / lung_a**2 + (Y - lung_cy)**2 / lung_b**2) <= 1.0
right_lung = ((X - lung_right_cx)**2 / lung_a**2 + (Y - lung_cy)**2 / lung_b**2) <= 1.0

# Fill volumes
for z in range(20, nz - 20):
    # Soft tissue body wall
    ct_data[:, :, z][body_mask & ~left_lung & ~right_lung] = np.random.normal(40, 15, 
        np.sum(body_mask & ~left_lung & ~right_lung)).astype(np.int16)
    
    # Lungs (air)
    ct_data[:, :, z][left_lung | right_lung] = np.random.normal(-850, 50,
        np.sum(left_lung | right_lung)).astype(np.int16)

# Create a nodule in the right lung
# Nodule parameters: 11mm diameter (Category 4A range)
nodule_diameter_mm = 11.0
nodule_radius_voxels = nodule_diameter_mm / 2.0 / spacing[0]

# Place nodule in right upper lobe area
nodule_cx = lung_right_cx + 10
nodule_cy = lung_cy - 20
nodule_cz = nz // 2 + 20

# Convert to RAS coordinates for the target file
nodule_ras = [
    nodule_cx * spacing[0],
    nodule_cy * spacing[1],
    nodule_cz * spacing[2]
]

# Create spherical nodule
for z in range(nz):
    for x in range(nx):
        for y in range(ny):
            dist = np.sqrt(
                ((x - nodule_cx) * spacing[0])**2 + 
                ((y - nodule_cy) * spacing[1])**2 + 
                ((z - nodule_cz) * spacing[2])**2
            )
            if dist <= nodule_diameter_mm / 2.0:
                # Solid nodule: soft tissue density
                ct_data[x, y, z] = np.random.normal(35, 10)

# Save NIfTI volume
ct_nii = nib.Nifti1Image(ct_data, affine)
ct_path = os.path.join(lidc_dir, f"{patient_id}_ct.nii.gz")
nib.save(ct_nii, ct_path)
print(f"Synthetic CT saved: {ct_path}")

# Create nodule target file for agent
target_info = {
    "patient_id": patient_id,
    "nodule_ras_mm": nodule_ras,
    "anatomical_location": "right upper lobe",
    "hint": "Look for a rounded soft-tissue density structure in the right lung"
}

target_path = os.path.join(lidc_dir, "nodule_target.json")
with open(target_path, "w") as f:
    json.dump(target_info, f, indent=2)
print(f"Target file saved: {target_path}")

# Save ground truth
gt_info = {
    "patient_id": patient_id,
    "nodule_center_ras": nodule_ras,
    "ground_truth_diameter_mm": float(nodule_diameter_mm),
    "correct_lungrads_category": "4A",
    "correct_recommendation": "3-month follow-up CT or PET-CT",
    "data_source": "synthetic"
}

gt_path = os.path.join(gt_dir, f"{patient_id}_nodule_gt.json")
os.makedirs(gt_dir, exist_ok=True)
with open(gt_path, "w") as f:
    json.dump(gt_info, f, indent=2)
print(f"Ground truth saved: {gt_path}")

# Mark that we're using synthetic data
with open("/tmp/lidc_data_type", "w") as f:
    f.write("synthetic")

print(f"\nSynthetic data created with {nodule_diameter_mm}mm nodule")
print(f"Category: 4A (8-15mm range)")
PYEOF

    CT_FILE="$LIDC_DIR/${PATIENT_ID}_ct.nii.gz"
else
    echo "DICOM files found: $DICOM_COUNT"
    CT_FILE="$DICOM_DIR"
    
    # For DICOM, create nodule target from annotations
    if [ -f "$GROUND_TRUTH_DIR/${PATIENT_ID}_nodules.json" ]; then
        echo "Creating nodule target from LIDC annotations..."
        python3 << 'PYEOF'
import os
import json
import numpy as np

gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
lidc_dir = os.environ.get("LIDC_DIR", "/home/ga/Documents/SlicerData/LIDC")
patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0001")

gt_path = os.path.join(gt_dir, f"{patient_id}_nodules.json")
if not os.path.exists(gt_path):
    print(f"Ground truth not found: {gt_path}")
    exit(0)

with open(gt_path) as f:
    gt_data = json.load(f)

nodules = gt_data.get("nodules", [])
if not nodules:
    print("No nodules in ground truth")
    exit(0)

# Find the most suitable nodule for measurement (ideally 6-20mm)
best_nodule = None
best_score = -1

for nod in nodules:
    diam = nod.get("diameter_mm", nod.get("diameter_pixels", 0))
    if 6 <= diam <= 20:
        score = 10 - abs(diam - 12)  # Prefer ~12mm nodules
    elif diam > 3:
        score = 5 - abs(diam - 12) / 5
    else:
        continue
    
    if score > best_score:
        best_score = score
        best_nodule = nod

if not best_nodule:
    best_nodule = nodules[0]

# Get nodule info
nodule_center = best_nodule.get("centroid_xyz", best_nodule.get("centroid_ras", [0, 0, 0]))
nodule_diameter = best_nodule.get("diameter_mm", best_nodule.get("diameter_pixels", 10))

# Determine Lung-RADS category
if nodule_diameter < 6:
    category = "2"
    recommendation = "Annual low-dose CT screening"
elif nodule_diameter < 8:
    category = "3"
    recommendation = "6-month follow-up low-dose CT"
elif nodule_diameter < 15:
    category = "4A"
    recommendation = "3-month follow-up CT or PET-CT"
else:
    category = "4B"
    recommendation = "Chest CT with/without contrast, PET-CT, or tissue sampling"

# Create target file for agent
target_info = {
    "patient_id": patient_id,
    "nodule_ras_mm": nodule_center,
    "anatomical_location": "lung (see coordinates)",
    "hint": "Navigate to the RAS coordinates and look for a rounded opacity"
}

target_path = os.path.join(lidc_dir, "nodule_target.json")
with open(target_path, "w") as f:
    json.dump(target_info, f, indent=2)
print(f"Target file created: {target_path}")

# Update ground truth with classification
gt_info = {
    "patient_id": patient_id,
    "nodule_center_ras": nodule_center,
    "ground_truth_diameter_mm": float(nodule_diameter),
    "correct_lungrads_category": category,
    "correct_recommendation": recommendation,
    "data_source": "LIDC-IDRI"
}

gt_out_path = os.path.join(gt_dir, f"{patient_id}_nodule_gt.json")
with open(gt_out_path, "w") as f:
    json.dump(gt_info, f, indent=2)
print(f"Ground truth updated: {gt_out_path}")

with open("/tmp/lidc_data_type", "w") as f:
    f.write("real")

print(f"\nSelected nodule: {nodule_diameter:.1f}mm, Category {category}")
PYEOF
    fi
fi

# Clean up any previous task artifacts
rm -f "$LIDC_DIR/nodule_measurement.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/lungrads_report.json" 2>/dev/null || true
rm -f /tmp/lung_nodule_result.json 2>/dev/null || true

# Verify nodule target file exists
if [ ! -f "$LIDC_DIR/nodule_target.json" ]; then
    echo "ERROR: Nodule target file not created!"
    exit 1
fi

echo "Nodule target file:"
cat "$LIDC_DIR/nodule_target.json"

# Create Slicer Python script to load CT
cat > /tmp/load_chest_ct.py << PYEOF
import slicer
import os

lidc_dir = "$LIDC_DIR"
patient_id = "$PATIENT_ID"

# Try loading NIfTI first (synthetic data), then DICOM
nifti_path = os.path.join(lidc_dir, f"{patient_id}_ct.nii.gz")
dicom_dir = os.path.join(lidc_dir, patient_id, "DICOM")

volume_node = None

if os.path.exists(nifti_path):
    print(f"Loading NIfTI: {nifti_path}")
    volume_node = slicer.util.loadVolume(nifti_path)
elif os.path.isdir(dicom_dir):
    print(f"Loading DICOM: {dicom_dir}")
    from DICOMLib import DICOMUtils
    with DICOMUtils.TemporaryDICOMDatabase() as db:
        DICOMUtils.importDicom(dicom_dir, db)
        patientUIDs = db.patients()
        if patientUIDs:
            loadedNodeIDs = DICOMUtils.loadPatientByUID(patientUIDs[0])
            if loadedNodeIDs:
                volume_node = slicer.mrmlScene.GetNodeByID(loadedNodeIDs[0])
else:
    print("ERROR: No CT data found!")

if volume_node:
    volume_node.SetName("ChestCT")
    
    # Set lung window/level
    displayNode = volume_node.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(1500)
        displayNode.SetLevel(-500)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        compositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        compositeNode.SetBackgroundVolumeID(volume_node.GetID())
    
    slicer.util.resetSliceViews()
    
    # Try to center on nodule location
    try:
        import json
        target_path = os.path.join(lidc_dir, "nodule_target.json")
        if os.path.exists(target_path):
            with open(target_path) as f:
                target = json.load(f)
            ras = target.get("nodule_ras_mm", [0, 0, 0])
            
            # Set slice offsets to nodule location
            for color in ["Red", "Green", "Yellow"]:
                sliceWidget = slicer.app.layoutManager().sliceWidget(color)
                sliceLogic = sliceWidget.sliceLogic()
                sliceNode = sliceLogic.GetSliceNode()
                
                if color == "Red":  # Axial
                    sliceNode.SetSliceOffset(ras[2])
                elif color == "Green":  # Coronal
                    sliceNode.SetSliceOffset(ras[1])
                else:  # Sagittal
                    sliceNode.SetSliceOffset(ras[0])
            
            print(f"Centered on nodule location: {ras}")
    except Exception as e:
        print(f"Could not center on nodule: {e}")
    
    print(f"CT loaded with lung window (W=1500, L=-500)")
else:
    print("WARNING: Could not load CT volume")

print("Setup complete - ready for nodule measurement task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the load script
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_chest_ct.py > /tmp/slicer_launch.log 2>&1 &

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
    
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 5

# Take initial screenshot
take_screenshot /tmp/lung_nodule_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Lung Nodule Measurement and Lung-RADS Classification"
echo "==========================================================="
echo ""
echo "A pulmonary nodule has been detected in this chest CT."
echo ""
echo "Instructions:"
echo "  1. Read nodule coordinates from: ~/Documents/SlicerData/LIDC/nodule_target.json"
echo "  2. Navigate to the nodule location in the CT scan"
echo "  3. Find the slice with the largest nodule cross-section"
echo "  4. Measure the longest diameter using Markups > Line tool"
echo "  5. Classify according to Lung-RADS criteria"
echo "  6. Save measurement and report"
echo ""
echo "Output files:"
echo "  - Measurement: ~/Documents/SlicerData/LIDC/nodule_measurement.mrk.json"
echo "  - Report: ~/Documents/SlicerData/LIDC/lungrads_report.json"
echo ""