#!/bin/bash
echo "=== Exporting generate_camera_reference_library results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/Documents/ReferenceImages"

# 1. Get Ground Truth: Actual list of cameras from API
echo "Fetching ground truth camera list..."
# We use python to format it as a clean JSON list of objects
CAMERAS_JSON=$(nx_api_get "/rest/v1/devices" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Extract only what we need: id and name
    clean = [{'id': d['id'], 'name': d['name']} for d in data]
    print(json.dumps(clean))
except:
    print('[]')
" 2>/dev/null)

# 2. Analyze Output Directory
echo "Analyzing output files..."
FILES_JSON="[]"
DIR_EXISTS="false"

if [ -d "$OUTPUT_DIR" ]; then
    DIR_EXISTS="true"
    # Construct a JSON array of file info: name, size, mtime, type
    # We use a loop to build the JSON carefully
    FILES_JSON=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.jpg" -printf '{"name":"%f","size":%s,"mtime":%T@},\n' | sed '$s/,$//')
    FILES_JSON="[$FILES_JSON]"
    
    # Check if files are valid images using 'file' command
    # We'll create a simple map of filename -> valid_image (bool)
    echo "Checking image validity..."
    IMAGE_VALIDITY_JSON=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.jpg" -exec sh -c '
        is_valid="false"
        if file "$1" | grep -q "JPEG image"; then is_valid="true"; fi
        echo "\"$(basename "$1")\": $is_valid,"
    ' sh {} \; | sed '$s/,$//')
    IMAGE_VALIDITY_JSON="{ $IMAGE_VALIDITY_JSON }"
else
    IMAGE_VALIDITY_JSON="{}"
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Compile Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "dir_exists": $DIR_EXISTS,
    "ground_truth_cameras": $CAMERAS_JSON,
    "output_files": $FILES_JSON,
    "image_validity": $IMAGE_VALIDITY_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="