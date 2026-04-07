#!/bin/bash
echo "=== Exporting dicomize_jpeg_image task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/DICOM/exports"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

FILE_CREATED_DURING_TASK="false"
OUTPUT_EXISTS="false"
DICOM_METADATA="{}"
LATEST_DCM=""

# Find the most recently modified .dcm file in the exports directory
LATEST_DCM=$(ls -t "$EXPORT_DIR"/*.dcm 2>/dev/null | head -1)

if [ -n "$LATEST_DCM" ] && [ -f "$LATEST_DCM" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$LATEST_DCM" 2>/dev/null || echo "0")
    
    # Check if created/modified after task started
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Extract metadata using pydicom
    DICOM_METADATA=$(python3 << PYEOF
import json
import sys
try:
    import pydicom
    ds = pydicom.dcmread("$LATEST_DCM", force=True)
    
    # Safely extract tags, allowing for formatting variations like Doe^John^^^
    def clean_val(val):
        if val is None: return ""
        v = str(val).strip()
        # Remove trailing carets for name formatting safety
        while v.endswith('^'): v = v[:-1]
        return v
        
    print(json.dumps({
        "success": True,
        "patient_name": clean_val(ds.PatientName) if hasattr(ds, 'PatientName') else "",
        "patient_id": clean_val(ds.PatientID) if hasattr(ds, 'PatientID') else "",
        "modality": clean_val(ds.Modality) if hasattr(ds, 'Modality') else ""
    }))
except Exception as e:
    print(json.dumps({"success": False, "error": str(e)}))
PYEOF
    )
fi

APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "latest_file": "$LATEST_DCM",
    "dicom_metadata": $DICOM_METADATA,
    "app_was_running": $APP_RUNNING
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="