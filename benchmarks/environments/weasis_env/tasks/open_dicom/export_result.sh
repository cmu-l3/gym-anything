#!/bin/bash
echo "=== Exporting open_dicom task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check if a DICOM is loaded by examining:
# 1. Window title changes (Weasis shows patient info when image is loaded)
# 2. Weasis log file
# 3. Screenshot analysis

FOUND="false"
DICOM_INFO=""
WINDOW_TITLE=""

# Get Weasis window title
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l | grep -i "weasis" | head -1 | cut -d' ' -f5-)

# Check if window title indicates a loaded image
# When Weasis loads a DICOM, the title usually changes to include patient/study info
if echo "$WINDOW_TITLE" | grep -qiE "(patient|study|test|CT|MR|slice|series|dcm)"; then
    FOUND="true"
    DICOM_INFO="$WINDOW_TITLE"
fi

# Alternative check: Look for specific DICOM loading indicators in log
# Weasis logs "DicomMediaIO" and "DicomSeries" when loading images
if [ "$FOUND" = "false" ]; then
    # Check for specific log patterns that indicate actual image loading
    if grep -qE "(DicomMediaIO|DicomSeries|MediaSeriesGroup.*add|loaded.*frame)" /tmp/weasis_ga.log 2>/dev/null; then
        FOUND="true"
        DICOM_INFO="DICOM loading confirmed in logs"
    fi
fi

# Alternative: Check if DICOM path appears in log (file was opened)
if [ "$FOUND" = "false" ]; then
    if grep -qE "/home/ga/DICOM/|\.dcm" /tmp/weasis_ga.log 2>/dev/null; then
        FOUND="true"
        DICOM_INFO="DICOM file path found in logs"
    fi
fi

# Alternative: Check if any DICOM files were recently accessed
RECENT_DICOM=$(find /home/ga/DICOM/samples -type f \( -name "*.dcm" -o -name "*.DCM" \) -mmin -5 2>/dev/null | head -1)
if [ -n "$RECENT_DICOM" ] && [ "$FOUND" = "false" ]; then
    # Get metadata from the DICOM file
    DICOM_METADATA=$(python3 << PYEOF
import json
try:
    import pydicom
    ds = pydicom.dcmread("$RECENT_DICOM")
    print(json.dumps({
        "patient_name": str(ds.PatientName) if hasattr(ds, 'PatientName') else None,
        "modality": str(ds.Modality) if hasattr(ds, 'Modality') else None,
        "study_description": str(ds.StudyDescription) if hasattr(ds, 'StudyDescription') else None
    }))
except:
    print("{}")
PYEOF
)
    if [ -n "$DICOM_METADATA" ] && [ "$DICOM_METADATA" != "{}" ]; then
        DICOM_INFO="$DICOM_METADATA"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "found": $FOUND,
    "window_title": "$WINDOW_TITLE",
    "dicom_info": "$DICOM_INFO",
    "recent_dicom_accessed": "$RECENT_DICOM",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
