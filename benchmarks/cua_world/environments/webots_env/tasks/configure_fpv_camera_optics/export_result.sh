#!/bin/bash
echo "=== Exporting configure_fpv_camera_optics result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/Desktop/drone_fpv_realistic.wbt"

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_FILE"
fi

# Parse the Webots file using Python to reliably extract hierarchical node data
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 -c "
import json
import re

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'file_exists': $FILE_EXISTS,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'file_size_bytes': $FILE_SIZE,
    'camera_found': False,
    'noise': None,
    'motion_blur': None,
    'has_lens': False,
    'radial_coeff_1': None,
    'radial_coeff_2': None
}

if result['file_exists']:
    try:
        with open('$OUTPUT_FILE', 'r') as f:
            content = f.read()
            
        # Locate the fpv_camera node
        cam_idx = content.find('name \"fpv_camera\"')
        if cam_idx == -1:
            cam_idx = content.find('fpv_camera Camera')
            
        if cam_idx != -1:
            result['camera_found'] = True
            
            # Extract properties within the camera scope
            # Look backwards to find the start of the camera, and forwards to capture its content
            start_idx = content.rfind('Camera {', 0, cam_idx)
            if start_idx == -1:
                start_idx = max(0, cam_idx - 100)
                
            # Grab a generous chunk representing the camera node
            segment = content[start_idx:start_idx+2000]
            
            noise_m = re.search(r'noise\s+([\d.]+)', segment)
            if noise_m:
                result['noise'] = float(noise_m.group(1))
                
            blur_m = re.search(r'motionBlur\s+([\d.]+)', segment)
            if blur_m:
                result['motion_blur'] = float(blur_m.group(1))
                
            if 'lens Lens' in segment:
                result['has_lens'] = True
                lens_idx = segment.find('lens Lens')
                lens_segment = segment[lens_idx:lens_idx+500]
                
                rc_m = re.search(r'radialCoefficients\s+([\d.-]+)\s+([\d.-]+)', lens_segment)
                if rc_m:
                    result['radial_coeff_1'] = float(rc_m.group(1))
                    result['radial_coeff_2'] = float(rc_m.group(2))
    except Exception as e:
        result['error'] = str(e)

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# Safely copy to standard output location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json:"
cat /tmp/task_result.json

echo "=== Export Complete ==="