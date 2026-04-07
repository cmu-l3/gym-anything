#!/bin/bash
echo "=== Exporting dicomize_clinical_photo task result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

EXPORT_DIR="/home/ga/DICOM/exports"
DICOM_FOUND="false"
LATEST_DICOM=""
FILE_CREATED_DURING_TASK="false"

# Find the most recently modified DICOM file in the export directory
LATEST_DICOM=$(find "$EXPORT_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" \) -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)

if [ -n "$LATEST_DICOM" ] && [ -f "$LATEST_DICOM" ]; then
    DICOM_FOUND="true"
    # Verify timestamp (anti-gaming)
    FILE_MTIME=$(stat -c %Y "$LATEST_DICOM" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Extract DICOM Metadata using pydicom
    METADATA_JSON=$(python3 << PYEOF
import json
import sys
import os

try:
    import pydicom
    ds = pydicom.dcmread("$LATEST_DICOM")
    
    res = {
        "patient_name": str(ds.PatientName) if 'PatientName' in ds else "",
        "patient_id": str(ds.PatientID) if 'PatientID' in ds else "",
        "modality": str(ds.Modality) if 'Modality' in ds else "",
        "has_pixel_data": 'PixelData' in ds,
        "file_size_bytes": os.path.getsize("$LATEST_DICOM")
    }
    print(json.dumps(res))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)
else:
    METADATA_JSON='{"error": "No DICOM file found"}'
fi

# Create result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "dicom_found": $DICOM_FOUND,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "latest_dicom_path": "$LATEST_DICOM",
    "metadata": $METADATA_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="