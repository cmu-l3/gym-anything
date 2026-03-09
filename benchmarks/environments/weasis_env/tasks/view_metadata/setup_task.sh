#!/bin/bash
echo "=== Setting up view_metadata task ==="

source /workspace/scripts/task_utils.sh

SAMPLE_DIR="/home/ga/DICOM/samples"
DICOM_FILE=$(find "$SAMPLE_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) 2>/dev/null | head -1)

if [ -z "$DICOM_FILE" ]; then
    echo "Creating sample DICOM file with metadata..."
    mkdir -p "$SAMPLE_DIR/synthetic"
    python3 << 'PYEOF'
import os
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    def create_sample_dicom(filename, size=256):
        file_meta = Dataset()
        file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'
        file_meta.MediaStorageSOPInstanceUID = generate_uid()
        file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
        ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\0" * 128)
        dt = datetime.datetime.now()
        ds.ContentDate = dt.strftime('%Y%m%d')
        ds.ContentTime = dt.strftime('%H%M%S.%f')
        ds.StudyInstanceUID = generate_uid()
        ds.SeriesInstanceUID = generate_uid()
        ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
        ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
        ds.Modality = "CT"
        ds.PatientName = "Metadata^Test"
        ds.PatientID = "META001"
        ds.PatientBirthDate = "19850315"
        ds.PatientSex = "F"
        ds.PatientAge = "038Y"
        ds.StudyDescription = "CT Chest Abdomen"
        ds.SeriesDescription = "Axial Images"
        ds.InstitutionName = "Test Hospital"
        ds.ReferringPhysicianName = "Dr^Smith"
        ds.AccessionNumber = "ACC123456"
        ds.StudyID = "STUDY001"
        ds.SeriesNumber = 1
        ds.InstanceNumber = 1
        ds.SamplesPerPixel = 1
        ds.PhotometricInterpretation = "MONOCHROME2"
        ds.Rows = size
        ds.Columns = size
        ds.BitsAllocated = 16
        ds.BitsStored = 12
        ds.HighBit = 11
        ds.PixelRepresentation = 0
        ds.RescaleIntercept = -1024
        ds.RescaleSlope = 1
        ds.WindowCenter = 40
        ds.WindowWidth = 400
        ds.PixelSpacing = [0.5, 0.5]
        ds.SliceThickness = 5.0
        image = np.zeros((size, size), dtype=np.uint16)
        image[:, :] = 1000
        ds.PixelData = image.tobytes()
        ds.save_as(filename)
        print(f"Created: {filename}")
    sample_dir = "/home/ga/DICOM/samples/synthetic"
    os.makedirs(sample_dir, exist_ok=True)
    create_sample_dicom(os.path.join(sample_dir, "metadata_test.dcm"))
except Exception as e:
    print(f"Error: {e}")
PYEOF
    chown -R ga:ga "$SAMPLE_DIR"
    DICOM_FILE="$SAMPLE_DIR/synthetic/metadata_test.dcm"
fi

# Save expected metadata for verification
python3 << PYEOF > /tmp/expected_metadata.json
import json
try:
    import pydicom
    ds = pydicom.dcmread("$DICOM_FILE")
    metadata = {
        "patient_name": str(ds.PatientName) if hasattr(ds, 'PatientName') else None,
        "patient_id": str(ds.PatientID) if hasattr(ds, 'PatientID') else None,
        "modality": str(ds.Modality) if hasattr(ds, 'Modality') else None,
        "study_description": str(ds.StudyDescription) if hasattr(ds, 'StudyDescription') else None
    }
    print(json.dumps(metadata))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

pkill -f weasis 2>/dev/null || true
sleep 2

echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis '$DICOM_FILE' > /tmp/weasis_ga.log 2>&1 &"
sleep 8

wait_for_weasis 60

# Dismiss first-run dialog if it appears
sleep 2
dismiss_first_run_dialog

# Wait a bit more for UI to settle
sleep 2
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Open the DICOM header/metadata viewer in Weasis"
