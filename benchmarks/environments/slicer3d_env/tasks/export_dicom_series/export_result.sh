#!/bin/bash
echo "=== Exporting DICOM Export Task Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Define paths
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports/DICOM_Export"

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi
echo "Slicer running: $SLICER_RUNNING"

# Count DICOM files in export directory
echo "Checking export directory: $EXPORT_DIR"
DICOM_COUNT=0
TOTAL_SIZE=0
NEWEST_FILE_TIME=0
OLDEST_FILE_TIME=999999999999

if [ -d "$EXPORT_DIR" ]; then
    # Count files (DICOM files may have .dcm extension or no extension)
    DICOM_COUNT=$(find "$EXPORT_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" -o -type f \) 2>/dev/null | wc -l)
    
    # Calculate total size
    TOTAL_SIZE=$(find "$EXPORT_DIR" -type f -exec stat -c%s {} + 2>/dev/null | awk '{sum += $1} END {print sum}' || echo "0")
    if [ -z "$TOTAL_SIZE" ]; then TOTAL_SIZE=0; fi
    
    # Get file timestamps
    for f in "$EXPORT_DIR"/*; do
        if [ -f "$f" ]; then
            FTIME=$(stat -c%Y "$f" 2>/dev/null || echo "0")
            if [ "$FTIME" -gt "$NEWEST_FILE_TIME" ]; then
                NEWEST_FILE_TIME=$FTIME
            fi
            if [ "$FTIME" -lt "$OLDEST_FILE_TIME" ]; then
                OLDEST_FILE_TIME=$FTIME
            fi
        fi
    done
fi

echo "DICOM file count: $DICOM_COUNT"
echo "Total size: $TOTAL_SIZE bytes"

# Check if files were created during the task
FILES_CREATED_DURING_TASK="false"
if [ "$DICOM_COUNT" -gt 0 ] && [ "$NEWEST_FILE_TIME" -gt "$TASK_START" ]; then
    FILES_CREATED_DURING_TASK="true"
fi
echo "Files created during task: $FILES_CREATED_DURING_TASK"

# Validate DICOM files and extract metadata using pydicom
echo "Validating DICOM files..."
DICOM_VALIDATION=$(python3 << 'PYEOF'
import os
import sys
import json

export_dir = "/home/ga/Documents/SlicerData/Exports/DICOM_Export"

# Ensure pydicom is available
try:
    import pydicom
except ImportError:
    try:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pydicom"])
        import pydicom
    except Exception as e:
        print(json.dumps({
            "valid_dicom_count": 0,
            "invalid_files": 0,
            "patient_name": "",
            "study_description": "",
            "modality": "",
            "sample_series_uid": "",
            "validation_error": str(e)
        }))
        sys.exit(0)

result = {
    "valid_dicom_count": 0,
    "invalid_files": 0,
    "patient_name": "",
    "study_description": "",
    "modality": "",
    "sample_series_uid": "",
    "patient_name_matches": False,
    "study_description_matches": False,
    "has_pixel_data": False,
    "validation_error": ""
}

if not os.path.exists(export_dir):
    print(json.dumps(result))
    sys.exit(0)

expected_patient_name = "SlicerExportTest"
expected_study_desc = "Brain MRI Export"

files = [f for f in os.listdir(export_dir) if os.path.isfile(os.path.join(export_dir, f))]

for filename in files[:50]:  # Check up to 50 files for performance
    filepath = os.path.join(export_dir, filename)
    try:
        ds = pydicom.dcmread(filepath, force=True)
        result["valid_dicom_count"] += 1
        
        # Extract metadata from first valid file
        if result["valid_dicom_count"] == 1:
            # Patient Name
            if hasattr(ds, 'PatientName') and ds.PatientName:
                pn = str(ds.PatientName)
                result["patient_name"] = pn
                if expected_patient_name.lower() in pn.lower():
                    result["patient_name_matches"] = True
            
            # Study Description
            if hasattr(ds, 'StudyDescription') and ds.StudyDescription:
                sd = str(ds.StudyDescription)
                result["study_description"] = sd
                if expected_study_desc.lower() in sd.lower() or "export" in sd.lower() or "brain" in sd.lower():
                    result["study_description_matches"] = True
            
            # Modality
            if hasattr(ds, 'Modality'):
                result["modality"] = str(ds.Modality)
            
            # Series UID
            if hasattr(ds, 'SeriesInstanceUID'):
                result["sample_series_uid"] = str(ds.SeriesInstanceUID)
            
            # Check for pixel data
            if hasattr(ds, 'PixelData') and ds.PixelData:
                result["has_pixel_data"] = True
                
    except Exception as e:
        result["invalid_files"] += 1

# Estimate total valid files based on sample
if len(files) > 50 and result["valid_dicom_count"] > 0:
    valid_ratio = result["valid_dicom_count"] / min(50, len(files))
    result["valid_dicom_count"] = int(len(files) * valid_ratio)

print(json.dumps(result))
PYEOF
)

echo "DICOM validation result: $DICOM_VALIDATION"

# Parse validation results
VALID_DICOM_COUNT=$(echo "$DICOM_VALIDATION" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid_dicom_count', 0))" 2>/dev/null || echo "0")
PATIENT_NAME=$(echo "$DICOM_VALIDATION" | python3 -c "import json,sys; print(json.load(sys.stdin).get('patient_name', ''))" 2>/dev/null || echo "")
PATIENT_NAME_MATCHES=$(echo "$DICOM_VALIDATION" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('patient_name_matches', False) else 'false')" 2>/dev/null || echo "false")
STUDY_DESCRIPTION=$(echo "$DICOM_VALIDATION" | python3 -c "import json,sys; print(json.load(sys.stdin).get('study_description', ''))" 2>/dev/null || echo "")
STUDY_DESC_MATCHES=$(echo "$DICOM_VALIDATION" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('study_description_matches', False) else 'false')" 2>/dev/null || echo "false")
HAS_PIXEL_DATA=$(echo "$DICOM_VALIDATION" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('has_pixel_data', False) else 'false')" 2>/dev/null || echo "false")
MODALITY=$(echo "$DICOM_VALIDATION" | python3 -c "import json,sys; print(json.load(sys.stdin).get('modality', ''))" 2>/dev/null || echo "")

echo ""
echo "Validation Summary:"
echo "  Valid DICOM files: $VALID_DICOM_COUNT"
echo "  Patient Name: $PATIENT_NAME (matches: $PATIENT_NAME_MATCHES)"
echo "  Study Description: $STUDY_DESCRIPTION (matches: $STUDY_DESC_MATCHES)"
echo "  Modality: $MODALITY"
echo "  Has Pixel Data: $HAS_PIXEL_DATA"

# Get initial DICOM count
INITIAL_DICOM_COUNT=$(cat /tmp/initial_dicom_count.txt 2>/dev/null || echo "0")
NEW_FILES_COUNT=$((DICOM_COUNT - INITIAL_DICOM_COUNT))

# Check screenshot exists
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE=0
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c%s /tmp/task_final.png 2>/dev/null || echo "0")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "slicer_was_running": $SLICER_RUNNING,
    "export_directory": "$EXPORT_DIR",
    "export_dir_exists": $([ -d "$EXPORT_DIR" ] && echo "true" || echo "false"),
    "dicom_file_count": $DICOM_COUNT,
    "valid_dicom_count": $VALID_DICOM_COUNT,
    "total_size_bytes": $TOTAL_SIZE,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "newest_file_timestamp": $NEWEST_FILE_TIME,
    "initial_file_count": $INITIAL_DICOM_COUNT,
    "new_files_count": $NEW_FILES_COUNT,
    "patient_name": "$PATIENT_NAME",
    "patient_name_matches": $PATIENT_NAME_MATCHES,
    "study_description": "$STUDY_DESCRIPTION",
    "study_description_matches": $STUDY_DESC_MATCHES,
    "modality": "$MODALITY",
    "has_pixel_data": $HAS_PIXEL_DATA,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="