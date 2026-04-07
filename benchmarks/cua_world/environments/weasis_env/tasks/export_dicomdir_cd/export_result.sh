#!/bin/bash
echo "=== Exporting export_dicomdir_cd task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/DICOM/exports/patient_cd"
DIALOG_IMG="/home/ga/DICOM/exports/export_dialog.png"

DIR_EXISTS="false"
DICOMDIR_EXISTS="false"
DICOMDIR_VALID="false"
DICOM_FILE_COUNT=0
DIALOG_IMG_EXISTS="false"
DIALOG_IMG_VALID="false"

# Check if target directory was created
if [ -d "$EXPORT_DIR" ]; then
    DIR_EXISTS="true"
    
    # Check for exported DICOM files (Weasis usually puts them in a subfolder like DICOM/ or similar, so we search recursively)
    DICOM_FILE_COUNT=$(find "$EXPORT_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" -o -name "*.dicom" \) | wc -l)
    # Sometimes exported DICOMs have no extension, so if 0, count all files that aren't DICOMDIR
    if [ "$DICOM_FILE_COUNT" -eq 0 ]; then
        DICOM_FILE_COUNT=$(find "$EXPORT_DIR" -type f ! -name "DICOMDIR" ! -name "README*" ! -name "weasis*" | wc -l)
    fi

    # Check for DICOMDIR index file
    if [ -f "$EXPORT_DIR/DICOMDIR" ]; then
        DICOMDIR_EXISTS="true"
        
        # Verify it is a valid DICOMDIR using pydicom
        DICOMDIR_INFO=$(python3 << 'PYEOF'
import json
import sys
try:
    import pydicom
    from pydicom.errors import InvalidDicomError
    
    ds = pydicom.dcmread("$EXPORT_DIR/DICOMDIR")
    
    # 1.2.840.10008.1.3.10 is the Media Storage SOP Class UID for DICOMDIR
    if hasattr(ds, 'file_meta') and hasattr(ds.file_meta, 'MediaStorageSOPClassUID') and \
       ds.file_meta.MediaStorageSOPClassUID == '1.2.840.10008.1.3.10':
        print(json.dumps({"valid": True, "error": None}))
    else:
        print(json.dumps({"valid": False, "error": "Not a DICOMDIR SOP Class"}))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
)
        if echo "$DICOMDIR_INFO" | grep -q '"valid": true'; then
            DICOMDIR_VALID="true"
        fi
    fi
fi

# Check for export dialog screenshot
if [ -f "$DIALOG_IMG" ]; then
    DIALOG_IMG_EXISTS="true"
    IMG_MTIME=$(stat -c %Y "$DIALOG_IMG" 2>/dev/null || echo "0")
    if [ "$IMG_MTIME" -gt "$TASK_START" ]; then
        DIALOG_IMG_VALID="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dir_exists": $DIR_EXISTS,
    "dicomdir_exists": $DICOMDIR_EXISTS,
    "dicomdir_valid": $DICOMDIR_VALID,
    "dicom_file_count": $DICOM_FILE_COUNT,
    "dialog_img_exists": $DIALOG_IMG_EXISTS,
    "dialog_img_valid": $DIALOG_IMG_VALID,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy to /tmp for verifier
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="