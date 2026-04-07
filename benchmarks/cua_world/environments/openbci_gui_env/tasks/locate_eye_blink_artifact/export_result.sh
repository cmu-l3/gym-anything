#!/bin/bash
echo "=== Exporting Locate Eye Blink Artifact Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Output File
OUTPUT_FILE="/home/ga/blink_timestamp.txt"
USER_TIMESTAMP="-1"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Check creation time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content and try to parse number
    CONTENT=$(cat "$OUTPUT_FILE" | head -n 1 | tr -d '[:space:]')
    # Use python to safely parse float
    USER_TIMESTAMP=$(python3 -c "try: print(float('$CONTENT')); except: print('-1')" 2>/dev/null || echo "-1")
fi

# 2. Calculate Ground Truth (Run this inside the container to avoid exporting the huge EEG file)
# We calculate the timestamp of the first major peak in Channel 1
REC_PATH="/home/ga/Documents/OpenBCI_GUI/Recordings/OpenBCI-EEG-S001-EyesOpen.txt"
GROUND_TRUTH_RESULT=$(python3 -c "
import numpy as np
import sys

try:
    path = '$REC_PATH'
    # OpenBCI format: Comments start with %, then header, then data
    # We need to find where data starts.
    # Usually data is CSV. Col 0 is index, Col 1 is Ch1.
    
    data = []
    sample_rate = 250.0
    
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('%') or 'Sample' in line:
                continue
            parts = line.split(',')
            if len(parts) > 2:
                # Append Channel 1 (index 1)
                try:
                    data.append(float(parts[1]))
                except:
                    pass
    
    arr = np.array(data)
    
    # Simple Blink Detector
    # Blinks are large deviations. Remove DC offset first.
    if len(arr) == 0:
        print('{\"error\": \"Empty data\"}')
        sys.exit(0)
        
    baseline = np.mean(arr)
    centered = np.abs(arr - baseline)
    
    # Threshold: 80 uV is a typical blink threshold for OpenBCI scale
    # Find first index crossing threshold
    threshold = 80.0
    candidates = np.where(centered > threshold)[0]
    
    if len(candidates) == 0:
        # Fallback: find absolute max in first 10 seconds
        limit = int(10 * sample_rate)
        idx = np.argmax(centered[:limit])
        print(f'{{\"timestamp\": {idx/sample_rate:.3f}, \"peak_uv\": {centered[idx]:.1f}, \"method\": \"max_fallback\"}}')
    else:
        # Find the local peak near the first crossing
        first_crossing = candidates[0]
        # Search window: -50ms to +400ms around crossing
        start = max(0, first_crossing - 12) 
        end = min(len(centered), first_crossing + 100)
        
        local_max_idx = start + np.argmax(centered[start:end])
        timestamp = local_max_idx / sample_rate
        print(f'{{\"timestamp\": {timestamp:.3f}, \"peak_uv\": {centered[local_max_idx]:.1f}, \"method\": \"threshold\"}}')

except Exception as e:
    print(f'{{\"error\": \"{str(e)}\"}}')
")

# 3. Check App State
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file_exists": $FILE_EXISTS,
    "output_created_during_task": $FILE_CREATED_DURING_TASK,
    "user_timestamp": $USER_TIMESTAMP,
    "ground_truth": $GROUND_TRUTH_RESULT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="