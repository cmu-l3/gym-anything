#!/bin/bash
echo "=== Exporting extract_dicom_uids task result ==="

if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# Capture final state
take_screenshot /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DICOM_FILE=$(cat /tmp/task_dicom_file.txt 2>/dev/null)

AGENT_TXT="/home/ga/DICOM/exports/routing_info.txt"
AGENT_IMG="/home/ga/DICOM/exports/dicom_info_screen.png"

TXT_EXISTS="false"
TXT_VALID_TIME="false"
TXT_CONTENT_B64=""

IMG_EXISTS="false"
IMG_VALID_TIME="false"

# Check Text File
if [ -f "$AGENT_TXT" ]; then
    TXT_EXISTS="true"
    MTIME=$(stat -c %Y "$AGENT_TXT" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        TXT_VALID_TIME="true"
    fi
    TXT_CONTENT_B64=$(cat "$AGENT_TXT" | base64 -w 0)
fi

# Check Image File
if [ -f "$AGENT_IMG" ]; then
    IMG_EXISTS="true"
    MTIME=$(stat -c %Y "$AGENT_IMG" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        IMG_VALID_TIME="true"
    fi
fi

# Programmatically Extract Ground Truth from DICOM File
GT_JSON="{}"
if [ -n "$DICOM_FILE" ] && [ -f "$DICOM_FILE" ]; then
    GT_JSON=$(python3 -c "
import json
try:
    import pydicom
    ds = pydicom.dcmread('$DICOM_FILE')
    gt = {
        'PatientID': str(ds.PatientID) if hasattr(ds, 'PatientID') else '',
        'StudyInstanceUID': str(ds.StudyInstanceUID) if hasattr(ds, 'StudyInstanceUID') else '',
        'SeriesInstanceUID': str(ds.SeriesInstanceUID) if hasattr(ds, 'SeriesInstanceUID') else ''
    }
    print(json.dumps(gt))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null || echo "{}")
fi

# Compile JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "txt_exists": $TXT_EXISTS,
    "txt_valid_time": $TXT_VALID_TIME,
    "txt_content_b64": "$TXT_CONTENT_B64",
    "img_exists": $IMG_EXISTS,
    "img_valid_time": $IMG_VALID_TIME,
    "ground_truth": $GT_JSON,
    "dicom_file": "$DICOM_FILE"
}
EOF

# Move payload safely
rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="