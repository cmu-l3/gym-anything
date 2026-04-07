#!/bin/bash
set -e
echo "=== Exporting align_image_sequence result ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROC_DIR="/home/ga/AstroImages/processed/aligned_series"

# Check output files and timestamps
FILE_COUNT=$(ls -1 "$PROC_DIR"/*.fits 2>/dev/null | wc -l || echo "0")
NEW_FILE_COUNT=0

if [ "$FILE_COUNT" -gt 0 ]; then
    for f in "$PROC_DIR"/*.fits; do
        MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            NEW_FILE_COUNT=$((NEW_FILE_COUNT + 1))
        fi
    done
fi

# Check if app was actually running
APP_RUNNING=$(pgrep -f "AstroImageJ\|aij" > /dev/null && echo "true" || echo "false")

# Take final evidence screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract arrays from the first and last generated FITS files.
# By passing these lightweight numpy arrays to the verifier, we avoid needing Astropy installed on the host.
cat > /tmp/extract_arrays.py << 'EOF'
import os
import glob
import numpy as np
import json
from astropy.io import fits

proc_dir = "/home/ga/AstroImages/processed/aligned_series"
files = sorted(glob.glob(os.path.join(proc_dir, "*.fits")))

status = {"arrays_extracted": False, "error": ""}

if len(files) >= 2:
    try:
        # Load and sanitize data arrays for phase correlation
        d1 = np.nan_to_num(fits.getdata(files[0])).astype(np.float32)
        d2 = np.nan_to_num(fits.getdata(files[-1])).astype(np.float32)
        
        np.save('/tmp/aligned_first.npy', d1)
        np.save('/tmp/aligned_last.npy', d2)
        status["arrays_extracted"] = True
    except Exception as e:
        status["error"] = str(e)

with open('/tmp/array_status.json', 'w') as f:
    json.dump(status, f)
EOF

sudo -u ga python3 /tmp/extract_arrays.py
ARRAY_STATUS=$(cat /tmp/array_status.json 2>/dev/null || echo '{"arrays_extracted": false}')
ARRAYS_EXTRACTED=$(echo "$ARRAY_STATUS" | grep -o '"arrays_extracted": true' > /dev/null && echo "true" || echo "false")

# Assemble JSON Payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_count": $FILE_COUNT,
    "new_file_count": $NEW_FILE_COUNT,
    "app_was_running": $APP_RUNNING,
    "arrays_extracted": $ARRAYS_EXTRACTED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="