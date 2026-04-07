#!/bin/bash
echo "=== Exporting task result ==="

# Record task end
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

EXPECTED_FILE="/home/ga/Documents/SAM_Projects/agrivoltaic.sam"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Extract parameters from the .sam file using a robust Python script
# SAM files are often zlib-compressed JSON starting with a header
EXTRACTED_JSON=$(python3 << 'PYEOF'
import json, os, re, zlib

result = {
    "system_capacity": 0,
    "gcr": -1,
    "clearance_height": -1,
    "tracking_mode": -1,
    "is_bifacial": False
}

filepath = "/home/ga/Documents/SAM_Projects/agrivoltaic.sam"
if os.path.exists(filepath):
    try:
        with open(filepath, 'rb') as f:
            data = f.read()
            
        text = ""
        # Try zlib decompression (skipping header)
        idx = data.find(b'\x78\x9c')
        if idx != -1:
            try:
                text = zlib.decompress(data[idx:]).decode('utf-8', errors='ignore')
            except:
                pass
                
        # Fallback to plain text decoding if decompression fails
        if not text:
            text = data.decode('utf-8', errors='ignore')

        # Extract system capacity
        cap = re.search(r'"system_capacity"\s*:\s*([\d\.]+)', text)
        if cap: result["system_capacity"] = float(cap.group(1))

        # Extract GCR
        gcr = re.search(r'"subarray1_gcr"\s*:\s*([\d\.]+)', text)
        if gcr: result["gcr"] = float(gcr.group(1))

        # Extract clearance height
        ch = re.search(r'"subarray1_clearance_height"\s*:\s*([\d\.]+)', text)
        if ch: result["clearance_height"] = float(ch.group(1))

        # Extract tracking mode
        tm = re.search(r'"subarray1_track_mode"\s*:\s*([\d\.]+)', text)
        if tm: result["tracking_mode"] = float(tm.group(1))

        # Check bifaciality
        # Looks for bifacial model activation or bifaciality factor > 0
        bifacial_model = re.search(r'"subarray1_bifacial_model"\s*:\s*([\d\.]+)', text)
        bifacial_factor = re.search(r'"cec_bifaciality_factor"\s*:\s*([\d\.]+)', text)
        
        if bifacial_model and float(bifacial_model.group(1)) > 0:
            result["is_bifacial"] = True
        elif bifacial_factor and float(bifacial_factor.group(1)) > 0:
            result["is_bifacial"] = True
        elif "bifacial" in text.lower():
            result["is_bifacial"] = True
            
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# Create final JSON result
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson extracted "$EXTRACTED_JSON" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        system_capacity: $extracted.system_capacity,
        gcr: $extracted.gcr,
        clearance_height: $extracted.clearance_height,
        tracking_mode: $extracted.tracking_mode,
        is_bifacial: $extracted.is_bifacial,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="