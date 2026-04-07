#!/bin/bash
echo "=== Exporting export_document_inventory results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/project_inventory.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Output File Stats
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Anti-gaming: Check if file was modified AFTER task started
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
fi

# 2. Generate Ground Truth (Run inside container to access localhost API)
# We fetch the actual state of the repository NOW to compare with agent's output
echo "Fetching ground truth from Nuxeo API..."
GROUND_TRUTH_JSON=$(python3 -c '
import requests, json, os
from requests.auth import HTTPBasicAuth

try:
    auth = HTTPBasicAuth("Administrator", "Administrator")
    url = "http://localhost:8080/nuxeo/api/v1/path/default-domain/workspaces/Projects/@children"
    headers = {"X-NXproperties": "*"}
    
    # Fetch all children
    resp = requests.get(url, auth=auth, headers=headers)
    resp.raise_for_status()
    data = resp.json()
    
    # Filter and format exactly as requested in the task
    ground_truth = []
    for entry in data.get("entries", []):
        if entry.get("type") in ["File", "Note"]:
            props = entry.get("properties", {})
            ground_truth.append({
                "title": props.get("dc:title"),
                "type": entry.get("type"),
                "path": entry.get("path"),
                "creator": props.get("dc:creator"),
                "created": props.get("dc:created")
            })
            
    print(json.dumps(ground_truth))
except Exception as e:
    print(json.dumps({"error": str(e)}))
' 2>/dev/null || echo "[]")

# 3. Create Result JSON
# We embed the Ground Truth here so the host-side verifier can use it
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_path": "$OUTPUT_PATH",
    "ground_truth": $GROUND_TRUTH_JSON
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="