#!/bin/bash
echo "=== Setting up DICOM Metadata Verification Task ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
PATIENT_ID="LIDC-IDRI-0001"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_time_iso.txt

# Clean up any previous task artifacts
rm -f "$LIDC_DIR/dicom_qa_report.json" 2>/dev/null || true
rm -f "$LIDC_DIR/metadata_verification_screenshot.png" 2>/dev/null || true
rm -f /tmp/dicom_task_result.json 2>/dev/null || true

# Prepare LIDC data (downloads real DICOM data if not exists)
echo "Preparing LIDC-IDRI data..."
export PATIENT_ID GROUND_TRUTH_DIR
/workspace/scripts/prepare_lidc_data.sh "$PATIENT_ID"

# Get the actual patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

DICOM_DIR="$LIDC_DIR/$PATIENT_ID/DICOM"

echo "Using patient: $PATIENT_ID"
echo "DICOM directory: $DICOM_DIR"

# Verify DICOM files exist
DICOM_COUNT=$(find "$DICOM_DIR" -type f 2>/dev/null | wc -l)
if [ "$DICOM_COUNT" -lt 10 ]; then
    echo "ERROR: Not enough DICOM files found (found: $DICOM_COUNT)"
    exit 1
fi
echo "Found $DICOM_COUNT DICOM files"

# Create ground truth directory
mkdir -p "$GROUND_TRUTH_DIR"

# Extract ground truth metadata from DICOM headers using Python
echo "Extracting ground truth DICOM metadata..."
python3 << PYEOF
import os
import sys
import json
import glob

dicom_dir = "$DICOM_DIR"
gt_dir = "$GROUND_TRUTH_DIR"
patient_id = "$PATIENT_ID"

# Try to import pydicom
try:
    import pydicom
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pydicom"])
    import pydicom

print(f"Reading DICOM metadata from {dicom_dir}...")

# Find DICOM files
dcm_files = []
for root, dirs, files in os.walk(dicom_dir):
    for f in files:
        fpath = os.path.join(root, f)
        try:
            ds = pydicom.dcmread(fpath, force=True, stop_before_pixels=True)
            if hasattr(ds, 'Modality'):
                dcm_files.append((fpath, ds))
        except Exception:
            continue

if not dcm_files:
    print("ERROR: No readable DICOM files found")
    sys.exit(1)

print(f"Found {len(dcm_files)} readable DICOM files")

# Use first file for metadata
ds = dcm_files[0][1]

# Extract metadata
gt_metadata = {
    "patient_id": str(getattr(ds, 'PatientID', '')),
    "study_date": str(getattr(ds, 'StudyDate', '')),
    "modality": str(getattr(ds, 'Modality', '')),
    "series_description": str(getattr(ds, 'SeriesDescription', '')),
    "slice_thickness_mm": float(getattr(ds, 'SliceThickness', 0)),
    "pixel_spacing_mm": [float(x) for x in getattr(ds, 'PixelSpacing', [0, 0])],
    "rows": int(getattr(ds, 'Rows', 0)),
    "columns": int(getattr(ds, 'Columns', 0)),
    "number_of_slices": len(dcm_files),
    "manufacturer": str(getattr(ds, 'Manufacturer', '')),
    "institution_name": str(getattr(ds, 'InstitutionName', '')),
    "study_instance_uid": str(getattr(ds, 'StudyInstanceUID', '')),
    "series_instance_uid": str(getattr(ds, 'SeriesInstanceUID', '')),
}

# Format study date if available
if gt_metadata["study_date"] and len(gt_metadata["study_date"]) == 8:
    d = gt_metadata["study_date"]
    gt_metadata["study_date_formatted"] = f"{d[:4]}-{d[4:6]}-{d[6:8]}"
else:
    gt_metadata["study_date_formatted"] = gt_metadata["study_date"]

# Save ground truth
gt_path = os.path.join(gt_dir, f"{patient_id}_dicom_gt.json")
with open(gt_path, 'w') as f:
    json.dump(gt_metadata, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(f"  Patient ID: {gt_metadata['patient_id']}")
print(f"  Modality: {gt_metadata['modality']}")
print(f"  Slice Thickness: {gt_metadata['slice_thickness_mm']} mm")
print(f"  Pixel Spacing: {gt_metadata['pixel_spacing_mm']} mm")
print(f"  Dimensions: {gt_metadata['rows']} x {gt_metadata['columns']} x {gt_metadata['number_of_slices']}")
print(f"  Manufacturer: {gt_metadata['manufacturer']}")
PYEOF

# Verify ground truth was created
if [ ! -f "$GROUND_TRUTH_DIR/${PATIENT_ID}_dicom_gt.json" ]; then
    echo "ERROR: Failed to create ground truth metadata"
    exit 1
fi
echo "Ground truth metadata verified (hidden from agent)"

# Set proper permissions on data
chown -R ga:ga "$LIDC_DIR" 2>/dev/null || true
chmod -R 755 "$LIDC_DIR" 2>/dev/null || true
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Save the patient ID for other scripts
echo "$PATIENT_ID" > /tmp/dicom_patient_id

# Kill any existing Slicer instances
echo "Stopping any existing Slicer instances..."
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Clear Slicer's DICOM database to ensure clean import test
echo "Clearing Slicer DICOM database for clean test..."
rm -rf /home/ga/.config/NA-MIC/Slicer*/DICOM 2>/dev/null || true
rm -rf /home/ga/.local/share/Slicer*/DICOM 2>/dev/null || true

# Launch Slicer WITHOUT loading any data (agent must import DICOM)
echo "Launching 3D Slicer (no data pre-loaded)..."
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
wait_for_slicer 90
sleep 5

# Configure window
echo "Configuring Slicer window..."
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

# Wait for UI to stabilize
sleep 3

# Take initial screenshot
take_screenshot /tmp/dicom_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: DICOM Import and Metadata Verification"
echo "============================================="
echo ""
echo "You are performing QA on an incoming CT dataset."
echo ""
echo "Your goal:"
echo "  1. Open the DICOM module in 3D Slicer"
echo "  2. Import DICOM data from: ~/Documents/SlicerData/LIDC/$PATIENT_ID/DICOM/"
echo "  3. Load the CT series into the scene"
echo "  4. Extract and verify metadata (Patient ID, Modality, dimensions, etc.)"
echo "  5. Create a QA report JSON at: ~/Documents/SlicerData/LIDC/dicom_qa_report.json"
echo "  6. Save a screenshot at: ~/Documents/SlicerData/LIDC/metadata_verification_screenshot.png"
echo ""
echo "The DICOM directory contains $DICOM_COUNT files."
echo ""