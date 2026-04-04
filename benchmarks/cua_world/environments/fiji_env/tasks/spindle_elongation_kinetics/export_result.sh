#!/bin/bash
echo "=== Exporting Spindle Elongation Kinetics results ==="

# 1. Get task timing
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Define paths
REPORT_PATH="/home/ga/Fiji_Data/results/spindle/velocity_report.txt"
IMAGE_PATH="/home/ga/Fiji_Data/results/spindle/spindle_projection.tif"

# 3. Check Image Artifact
IMAGE_EXISTS="false"
IMAGE_CREATED_DURING="false"
IMAGE_SIZE=0

if [ -f "$IMAGE_PATH" ]; then
    IMAGE_EXISTS="true"
    IMAGE_MTIME=$(stat -c %Y "$IMAGE_PATH" 2>/dev/null || echo "0")
    IMAGE_SIZE=$(stat -c %s "$IMAGE_PATH" 2>/dev/null || echo "0")
    
    if [ "$IMAGE_MTIME" -gt "$TASK_START" ]; then
        IMAGE_CREATED_DURING="true"
    fi
fi

# 4. Check Report Artifact and Parse Content
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
REPORT_CONTENT=""
REPORT_VALUES="{}"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    
    # Python script to extract numerical values from the free-text report
    REPORT_VALUES=$(python3 << EOF
import re
try:
    with open("$REPORT_PATH", 'r') as f:
        text = f.read()
    
    # Regex to find numbers associated with keys
    def extract(pattern, text):
        m = re.search(pattern, text, re.IGNORECASE)
        return float(m.group(1)) if m else None

    d_f30 = extract(r'Distance_F30.*?([\d\.]+)', text)
    d_f45 = extract(r'Distance_F45.*?([\d\.]+)', text)
    t_delta = extract(r'Time_Delta.*?([\d\.]+)', text)
    velocity = extract(r'Velocity.*?([\d\.]+)', text)

    import json
    print(json.dumps({
        "dist_f30": d_f30, 
        "dist_f45": d_f45, 
        "time_delta": t_delta, 
        "velocity": velocity
    }))
except Exception as e:
    print("{}")
EOF
)
fi

# 5. Take final screenshot for VLM verification
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Construct Result JSON
# Use a temp file to avoid permission issues with jq or complex piping
TEMP_JSON=$(mktemp)
cat << EOF > "$TEMP_JSON"
{
  "timestamp": $TASK_END,
  "task_start": $TASK_START,
  "image_exists": $IMAGE_EXISTS,
  "image_created_during_task": $IMAGE_CREATED_DURING,
  "image_size_bytes": $IMAGE_SIZE,
  "report_exists": $REPORT_EXISTS,
  "report_created_during_task": $REPORT_CREATED_DURING,
  "report_values": $REPORT_VALUES,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json