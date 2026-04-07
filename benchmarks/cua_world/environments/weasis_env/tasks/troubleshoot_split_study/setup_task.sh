#!/bin/bash
echo "=== Setting up troubleshoot_split_study task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming measure)
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs
rm -rf /home/ga/DICOM/qa_task
rm -f /home/ga/DICOM/exports/mismatch_report.txt
mkdir -p /home/ga/DICOM/qa_task
mkdir -p /home/ga/DICOM/exports

# Create ground truth directory (hidden from agent)
mkdir -p /var/lib/app/ground_truth
chmod 700 /var/lib/app/ground_truth

# Run Python script to generate real DICOMs with a randomized error
python3 << 'PYEOF'
import os
import random
import numpy as np
try:
    from pydicom.dataset import Dataset, FileDataset
    from pydicom.uid import generate_uid, ExplicitVRLittleEndian
    import datetime

    qa_dir = "/home/ga/DICOM/qa_task"
    
    study_uid = generate_uid()
    series_uid = generate_uid()
    patient_id = "QA_PATIENT_001"
    patient_name = "Split^StudyTest"
    
    filenames = []
    size = 256
    
    # Create base image data so the DICOM files are valid images
    image = np.zeros((size, size), dtype=np.uint16)
    for i in range(size):
        for j in range(size):
            image[i, j] = int((i + j) * 4000 / (2 * size))
    center = size // 2
    radius = size // 4
    for i in range(size):
        for j in range(size):
            if (i - center)**2 + (j - center)**2 < radius**2:
                image[i, j] = 2000
                
    image_bytes = image.tobytes()

    for i in range(1, 6):
        filename = f"slice_{i:03d}.dcm"
        filepath = os.path.join(qa_dir, filename)
        
        file_meta = Dataset()
        file_meta.MediaStorageSOPClassUID = '1.2.840.10008.5.1.4.1.1.2'
        file_meta.MediaStorageSOPInstanceUID = generate_uid()
        file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
        
        ds = FileDataset(filepath, {}, file_meta=file_meta, preamble=b"\0" * 128)
        
        dt = datetime.datetime.now()
        ds.ContentDate = dt.strftime('%Y%m%d')
        ds.ContentTime = dt.strftime('%H%M%S.%f')
        ds.StudyInstanceUID = study_uid
        ds.SeriesInstanceUID = series_uid
        ds.SOPInstanceUID = file_meta.MediaStorageSOPInstanceUID
        ds.SOPClassUID = file_meta.MediaStorageSOPClassUID
        ds.Modality = "CT"
        ds.PatientName = patient_name
        ds.PatientID = patient_id
        ds.StudyDescription = "QA Test Study"
        ds.SeriesDescription = "CT Axial"
        
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
        
        ds.PixelData = image_bytes
        ds.save_as(filepath)
        filenames.append(filename)

    # Pick one random file to corrupt (creates the "split study" effect)
    corrupt_idx = random.randint(0, 4)
    corrupt_filename = filenames[corrupt_idx]
    corrupt_filepath = os.path.join(qa_dir, corrupt_filename)
    
    import pydicom
    ds = pydicom.dcmread(corrupt_filepath)
    random_err = f"ERR_{random.randint(10000, 99999)}"
    ds.PatientID = random_err
    ds.StudyInstanceUID = generate_uid() 
    ds.save_as(corrupt_filepath)
    print(f"Corrupted file {corrupt_filename} with PatientID {random_err}")
    
    import json
    gt_dir = "/var/lib/app/ground_truth"
    gt_data = {
        "corrupted_filename": corrupt_filename,
        "mismatched_patient_id": random_err
    }
    with open(os.path.join(gt_dir, "qa_answer.json"), "w") as f:
        json.dump(gt_data, f)
        
except Exception as e:
    print(f"Error generating DICOM files: {e}")
PYEOF

# Fix permissions for the QA directory and exports
chown -R ga:ga /home/ga/DICOM/qa_task
chmod -R 755 /home/ga/DICOM/qa_task
chown ga:ga /home/ga/DICOM/exports

# Ensure Weasis is stopped before we launch it cleanly
pkill -f weasis 2>/dev/null || true
sleep 2

echo "Launching Weasis..."
su - ga -c "DISPLAY=:1 /snap/bin/weasis > /tmp/weasis_ga.log 2>&1 &" || \
su - ga -c "DISPLAY=:1 weasis > /tmp/weasis_ga.log 2>&1 &"

# Wait for Weasis to load
wait_for_weasis 60

# Dismiss standard startup dialog
sleep 2
dismiss_first_run_dialog
sleep 2

# Maximize and focus Weasis window
DISPLAY=:1 wmctrl -r "Weasis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Weasis" 2>/dev/null || true

# Take initial screenshot showing correct starting state
take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="