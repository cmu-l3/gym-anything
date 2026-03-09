#!/bin/bash
echo "=== Setting up Subcarinal Lymph Node Assessment Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_timestamp.txt

# Prepare LIDC data
echo "Preparing LIDC-IDRI chest CT data..."
/workspace/scripts/prepare_lidc_data.sh LIDC-IDRI-0001

# Get the patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

echo "Using patient: $PATIENT_ID"
DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"

# Verify DICOM data exists
DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "ERROR: Insufficient DICOM files found in $DICOM_DIR"
    exit 1
fi
echo "Found $DICOM_COUNT DICOM files"

# Clean up any previous task outputs
rm -f "$LIDC_DIR/subcarinal_measurement.mrk.json" 2>/dev/null || true
rm -f "$LIDC_DIR/lymph_node_report.json" 2>/dev/null || true
rm -f /tmp/subcarinal_task_result.json 2>/dev/null || true

# Generate ground truth for Station 7 assessment
echo "Generating anatomical ground truth..."
mkdir -p "$GROUND_TRUTH_DIR"

python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

# Ensure dependencies
try:
    import pydicom
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pydicom"])
    import pydicom

patient_id = os.environ.get("PATIENT_ID", "LIDC-IDRI-0001")
dicom_dir = os.environ.get("DICOM_DIR", f"/home/ga/Documents/SlicerData/LIDC/{patient_id}/DICOM")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")

print(f"Analyzing chest CT for patient: {patient_id}")
print(f"DICOM directory: {dicom_dir}")

# Load DICOM series and find anatomical landmarks
dcm_files = []
for root, dirs, files in os.walk(dicom_dir):
    for f in files:
        fpath = os.path.join(root, f)
        try:
            ds = pydicom.dcmread(fpath, force=True)
            if hasattr(ds, 'pixel_array') and hasattr(ds, 'SliceLocation'):
                dcm_files.append((float(ds.SliceLocation), ds, fpath))
        except Exception:
            continue

if not dcm_files:
    print("ERROR: No valid DICOM files with SliceLocation found")
    # Create default ground truth
    gt_data = {
        "patient_id": patient_id,
        "carina_z_mm": 0,
        "subcarinal_z_range_mm": [-5, -45],
        "subcarinal_center_xy_mm": [0, 0],
        "reference_lymph_node": {
            "present": False,
            "center_xyz": None,
            "short_axis_mm": None,
            "classification": "Normal"
        },
        "mediastinal_bounds": {
            "x_range_mm": [-50, 50],
            "y_range_mm": [-80, 20]
        },
        "data_quality": "fallback"
    }
else:
    # Sort by slice location
    dcm_files.sort(key=lambda x: x[0])
    
    # Get spacing info from first slice
    ds0 = dcm_files[0][1]
    pixel_spacing = list(ds0.PixelSpacing) if hasattr(ds0, 'PixelSpacing') else [1.0, 1.0]
    slice_thickness = float(ds0.SliceThickness) if hasattr(ds0, 'SliceThickness') else 1.0
    
    rows = int(ds0.Rows)
    cols = int(ds0.Columns)
    
    # Image center in mm
    image_center_x = (cols / 2) * float(pixel_spacing[0])
    image_center_y = (rows / 2) * float(pixel_spacing[1])
    
    # Find slice range
    z_positions = [s[0] for s in dcm_files]
    z_min, z_max = min(z_positions), max(z_positions)
    z_range = z_max - z_min
    
    print(f"Z range: {z_min:.1f} to {z_max:.1f} mm (span: {z_range:.1f} mm)")
    print(f"Pixel spacing: {pixel_spacing}")
    print(f"Slice thickness: {slice_thickness}")
    
    # Estimate carina location (typically around 60-70% from inferior in chest CT)
    # The carina is usually at T4-T5 vertebral level
    carina_z = z_min + z_range * 0.65
    
    # Subcarinal space extends ~40mm below carina
    subcarinal_superior = carina_z - 5  # Just below carina
    subcarinal_inferior = carina_z - 45  # ~40mm below
    
    # Mediastinum is roughly centered
    mediastinal_center_x = image_center_x
    mediastinal_center_y = image_center_y - 20  # Slightly posterior
    
    # Analyze slices in subcarinal region for potential lymph nodes
    # Look for intermediate-density structures in the mediastinum
    lymph_node_found = False
    ln_center = None
    ln_short_axis = None
    
    # Check slices in subcarinal region
    subcarinal_slices = [(z, ds) for z, ds, _ in dcm_files 
                          if subcarinal_inferior <= z <= subcarinal_superior]
    
    print(f"Analyzing {len(subcarinal_slices)} slices in subcarinal region")
    
    for z, ds in subcarinal_slices:
        try:
            img = ds.pixel_array.astype(float)
            
            # Apply rescale if available
            slope = float(ds.RescaleSlope) if hasattr(ds, 'RescaleSlope') else 1.0
            intercept = float(ds.RescaleIntercept) if hasattr(ds, 'RescaleIntercept') else 0.0
            hu = img * slope + intercept
            
            # Define mediastinal ROI (central region)
            roi_x_start = int(cols * 0.35)
            roi_x_end = int(cols * 0.65)
            roi_y_start = int(rows * 0.35)
            roi_y_end = int(rows * 0.65)
            
            roi = hu[roi_y_start:roi_y_end, roi_x_start:roi_x_end]
            
            # Look for lymph node-density tissue (20-60 HU typically)
            ln_mask = (roi > 20) & (roi < 70)
            ln_pixels = np.sum(ln_mask)
            
            # If we find a cluster of lymph node density
            if ln_pixels > 50:  # At least 50 pixels
                # Estimate size
                area_mm2 = ln_pixels * float(pixel_spacing[0]) * float(pixel_spacing[1])
                equiv_diameter = 2 * np.sqrt(area_mm2 / np.pi)
                
                if equiv_diameter >= 5 and equiv_diameter <= 30:  # Plausible LN size
                    lymph_node_found = True
                    
                    # Find centroid
                    y_indices, x_indices = np.where(ln_mask)
                    if len(x_indices) > 0:
                        cx = roi_x_start + np.mean(x_indices)
                        cy = roi_y_start + np.mean(y_indices)
                        
                        cx_mm = cx * float(pixel_spacing[0])
                        cy_mm = cy * float(pixel_spacing[1])
                        
                        ln_center = [float(cx_mm), float(cy_mm), float(z)]
                        ln_short_axis = float(equiv_diameter * 0.8)  # Short axis estimate
                        
                        print(f"Potential lymph node at z={z:.1f}: ~{ln_short_axis:.1f}mm")
                        break
        except Exception as e:
            continue
    
    # Determine classification
    if not lymph_node_found or ln_short_axis is None:
        classification = "Normal"
        ln_short_axis = None
    elif ln_short_axis < 10:
        classification = "Normal"
    elif ln_short_axis <= 15:
        classification = "Indeterminate"
    else:
        classification = "Pathologically Enlarged"
    
    gt_data = {
        "patient_id": patient_id,
        "carina_z_mm": float(carina_z),
        "subcarinal_z_range_mm": [float(subcarinal_superior), float(subcarinal_inferior)],
        "subcarinal_center_xy_mm": [float(mediastinal_center_x), float(mediastinal_center_y)],
        "reference_lymph_node": {
            "present": lymph_node_found,
            "center_xyz": ln_center,
            "short_axis_mm": ln_short_axis,
            "classification": classification
        },
        "mediastinal_bounds": {
            "x_range_mm": [float(mediastinal_center_x - 50), float(mediastinal_center_x + 50)],
            "y_range_mm": [float(mediastinal_center_y - 40), float(mediastinal_center_y + 40)]
        },
        "image_info": {
            "rows": rows,
            "cols": cols,
            "pixel_spacing_mm": [float(pixel_spacing[0]), float(pixel_spacing[1])],
            "slice_thickness_mm": slice_thickness,
            "z_range_mm": [float(z_min), float(z_max)]
        },
        "data_quality": "analyzed"
    }

# Save ground truth
gt_path = os.path.join(gt_dir, f"{patient_id}_station7_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_data, f, indent=2)

print(f"\nGround truth saved to {gt_path}")
print(f"Carina Z: {gt_data['carina_z_mm']:.1f} mm")
print(f"Subcarinal range: {gt_data['subcarinal_z_range_mm']}")
print(f"Lymph node present: {gt_data['reference_lymph_node']['present']}")
if gt_data['reference_lymph_node']['present']:
    print(f"  Short axis: {gt_data['reference_lymph_node']['short_axis_mm']:.1f} mm")
    print(f"  Classification: {gt_data['reference_lymph_node']['classification']}")
PYEOF

export PATIENT_ID DICOM_DIR GROUND_TRUTH_DIR

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${PATIENT_ID}_station7_gt.json" ]; then
    echo "WARNING: Ground truth generation may have failed, creating fallback"
    cat > "$GROUND_TRUTH_DIR/${PATIENT_ID}_station7_gt.json" << 'EOF'
{
    "patient_id": "LIDC-IDRI-0001",
    "carina_z_mm": 0,
    "subcarinal_z_range_mm": [-5, -45],
    "reference_lymph_node": {
        "present": false,
        "short_axis_mm": null,
        "classification": "Normal"
    },
    "data_quality": "fallback"
}
EOF
fi

echo "Ground truth created"

# Create Slicer Python script to load DICOM
cat > /tmp/load_lidc_ct.py << PYEOF
import slicer
import os
import DICOMLib

dicom_dir = "$DICOM_DIR"
patient_id = "$PATIENT_ID"

print(f"Loading chest CT from DICOM: {dicom_dir}")

# Load DICOM database
dicomBrowser = slicer.modules.DICOMWidget.browserWidget
dicomBrowser.dicomBrowser.importDirectory(dicom_dir, dicomBrowser.dicomBrowser.ImportDirectoryAddLink)

# Wait for import
slicer.app.processEvents()
import time
time.sleep(3)

# Try to load the series
from DICOMLib import DICOMUtils
patientUIDs = slicer.dicomDatabase.patients()
print(f"Found {len(patientUIDs)} patients in DICOM database")

loaded_volume = None
for patientUID in patientUIDs:
    studies = slicer.dicomDatabase.studiesForPatient(patientUID)
    for study in studies:
        series = slicer.dicomDatabase.seriesForStudy(study)
        for serie in series:
            files = slicer.dicomDatabase.filesForSeries(serie)
            if len(files) > 50:  # Likely the CT series
                print(f"Loading series with {len(files)} files")
                loadedNodes = DICOMUtils.loadSeriesByUID([serie])
                if loadedNodes:
                    loaded_volume = loadedNodes[0]
                    break
        if loaded_volume:
            break
    if loaded_volume:
        break

if loaded_volume:
    loaded_volume.SetName("ChestCT")
    print(f"Loaded volume: {loaded_volume.GetName()}")
    
    # Set initial window/level to lung window (to see airways for navigation)
    displayNode = loaded_volume.GetDisplayNode()
    if displayNode:
        displayNode.SetWindow(1500)
        displayNode.SetLevel(-500)
        displayNode.SetAutoWindowLevel(False)
    
    # Set as background in all views
    for color in ["Red", "Green", "Yellow"]:
        sliceCompositeNode = slicer.app.layoutManager().sliceWidget(color).sliceLogic().GetSliceCompositeNode()
        sliceCompositeNode.SetBackgroundVolumeID(loaded_volume.GetID())
    
    # Reset and center views
    slicer.util.resetSliceViews()
    
    # Start at a mid-thoracic level
    bounds = [0]*6
    loaded_volume.GetBounds(bounds)
    mid_z = (bounds[4] + bounds[5]) / 2
    
    for color in ["Red", "Green", "Yellow"]:
        sliceWidget = slicer.app.layoutManager().sliceWidget(color)
        sliceNode = sliceWidget.sliceLogic().GetSliceNode()
        if color == "Red":  # Axial
            sliceNode.SetSliceOffset(mid_z)
    
    print("Chest CT loaded - starting at mid-thoracic level")
    print("Navigate superiorly to find the carina (tracheal bifurcation)")
else:
    print("WARNING: Could not load DICOM volume")
    # Try alternative loading method
    import glob
    dcm_files = glob.glob(os.path.join(dicom_dir, "**", "*"), recursive=True)
    dcm_files = [f for f in dcm_files if os.path.isfile(f)][:1]
    if dcm_files:
        loaded_volume = slicer.util.loadVolume(dcm_files[0])
        if loaded_volume:
            loaded_volume.SetName("ChestCT")
            print("Loaded via alternative method")

print("Setup complete - ready for lymph node assessment task")
PYEOF

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer
echo "Launching 3D Slicer with chest CT..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/load_lidc_ct.py > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to fully load
wait_for_slicer 120
sleep 15

# Configure window
echo "Configuring Slicer window..."
WID=$(get_slicer_window_id)
if [ -n "$WID" ]; then
    echo "Found Slicer window: $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    
    focus_window "$WID"
fi

sleep 5

# Take initial screenshot
take_screenshot /tmp/subcarinal_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Subcarinal Lymph Node Station Assessment"
echo "==============================================="
echo ""
echo "You are given a chest CT scan for lung cancer staging."
echo ""
echo "Your objectives:"
echo "  1. Navigate to the carina (tracheal bifurcation)"
echo "  2. Move inferiorly to the subcarinal space (Station 7)"
echo "  3. Apply mediastinal window (W:350, L:40)"
echo "  4. Identify any lymph nodes in Station 7"
echo "  5. If found, measure the SHORT AXIS of the largest node"
echo "  6. Classify: Normal (<10mm), Indeterminate (10-15mm),"
echo "     or Pathologically Enlarged (>15mm)"
echo ""
echo "Save outputs to:"
echo "  - ~/Documents/SlicerData/LIDC/subcarinal_measurement.mrk.json"
echo "  - ~/Documents/SlicerData/LIDC/lymph_node_report.json"
echo ""