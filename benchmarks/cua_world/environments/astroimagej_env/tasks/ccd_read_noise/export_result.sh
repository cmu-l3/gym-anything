#!/bin/bash
echo "=== Exporting CCD Read Noise task result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target file paths
OUTPUT_FILE="/home/ga/AstroImages/measurements/ccd_read_noise.txt"
RESULT_JSON="/tmp/task_result.json"

# Python script to safely parse the output file and package results
python3 << PYEOF
import os
import json
import re

output_file = "$OUTPUT_FILE"
task_start = int("$TASK_START")

result = {
    "output_exists": False,
    "file_created_during_task": False,
    "parsed_values": {},
    "raw_content": "",
    "parse_errors": []
}

if os.path.exists(output_file):
    result["output_exists"] = True
    mtime = os.path.getmtime(output_file)
    if mtime > task_start:
        result["file_created_during_task"] = True
        
    try:
        with open(output_file, 'r') as f:
            content = f.read()
            result["raw_content"] = content[:1000]  # Cap length for safety
            
            # Extract key-value pairs
            lines = content.strip().split('\n')
            for line in lines:
                if '=' in line:
                    key, val = line.split('=', 1)
                    key = key.strip().lower()
                    val = val.strip()
                    
                    # Extract just the numeric part using regex
                    match = re.search(r'[-+]?\d*\.\d+|\d+', val)
                    if match:
                        try:
                            result["parsed_values"][key] = float(match.group())
                        except ValueError:
                            result["parse_errors"].append(f"Could not parse float from {val}")
    except Exception as e:
        result["parse_errors"].append(str(e))

with open("$RESULT_JSON", 'w') as f:
    json.dump(result, f, indent=2)

print("Export data generated:")
print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

# Close application gracefully if possible
if is_aij_running; then
    echo "Closing AstroImageJ..."
    close_astroimagej
fi

echo "=== Export complete ==="