#!/bin/bash
echo "=== Exporting anonymize_dicom_export task result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Extract task start time
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python within the container to parse the anonymized directory safely
# and generate a clean JSON output for the host verifier.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 << PYEOF
import os
import json
import pydicom

result = {
    "start_time": $START_TIME,
    "dir_exists": False,
    "files": [],
    "error": None
}

target_dir = "/home/ga/DICOM/anonymized"

try:
    if os.path.exists(target_dir) and os.path.isdir(target_dir):
        result["dir_exists"] = True
        
        for root, dirs, files in os.walk(target_dir):
            for f in files:
                fpath = os.path.join(root, f)
                # Try to read as DICOM
                try:
                    ds = pydicom.dcmread(fpath)
                    mtime = os.path.getmtime(fpath)
                    
                    file_info = {
                        "path": fpath,
                        "mtime": mtime,
                        "patient_name": str(getattr(ds, 'PatientName', '')),
                        "patient_id": str(getattr(ds, 'PatientID', '')),
                        "rows": int(getattr(ds, 'Rows', 0)),
                        "columns": int(getattr(ds, 'Columns', 0)),
                        "has_pixels": hasattr(ds, 'PixelData') and bool(ds.PixelData)
                    }
                    result["files"].append(file_info)
                except Exception as e:
                    pass  # Not a valid DICOM file or cannot be read
except Exception as e:
    result["error"] = str(e)

with open("$TEMP_JSON", "w") as fp:
    json.dump(result, fp)
PYEOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="