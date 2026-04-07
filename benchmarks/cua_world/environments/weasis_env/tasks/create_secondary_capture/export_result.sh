#!/bin/bash
echo "=== Exporting create_secondary_capture task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Target output file
OUTPUT_PATH="/home/ga/DICOM/exports/finding_sc.dcm"
FILE_CREATED_DURING_TASK="false"
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Use Python and pydicom to parse the exported DICOM file metadata securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 << PYEOF > "$TEMP_JSON"
import json
import os

output_path = "$OUTPUT_PATH"
result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": "$OUTPUT_EXISTS" == "true",
    "file_created_during_task": "$FILE_CREATED_DURING_TASK" == "true",
    "output_size_bytes": $OUTPUT_SIZE,
    "sop_class_uid": "",
    "photometric_interpretation": "",
    "parse_error": ""
}

if result["output_exists"]:
    try:
        import pydicom
        # Stop before pixels to read headers fast and safely
        ds = pydicom.dcmread(output_path, stop_before_pixels=True)
        result["sop_class_uid"] = str(getattr(ds, "SOPClassUID", ""))
        result["photometric_interpretation"] = str(getattr(ds, "PhotometricInterpretation", ""))
    except Exception as e:
        result["parse_error"] = str(e)

print(json.dumps(result))
PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="