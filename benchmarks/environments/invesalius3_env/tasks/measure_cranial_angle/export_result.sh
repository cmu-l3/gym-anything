#!/bin/bash
set -e
echo "=== Exporting measure_cranial_angle result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_end.png

# Task timestamp
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/cranial_angle.inv3"

# Analyze the output file using Python
python3 << 'PYEOF'
import tarfile
import plistlib
import os
import json
import time

output_file = "/home/ga/Documents/cranial_angle.inv3"
task_start = int(os.environ.get("TASK_START", 0))

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "valid_archive": False,
    "measurements_found": False,
    "angular_measurements_count": 0,
    "valid_angle_values_count": 0,
    "angle_values": [],
    "file_size_bytes": 0
}

if os.path.isfile(output_file):
    result["file_exists"] = True
    result["file_size_bytes"] = os.path.getsize(output_file)
    
    # Check timestamp
    mtime = os.path.getmtime(output_file)
    if mtime > task_start:
        result["file_created_during_task"] = True
    
    # Inspect archive contents
    try:
        if tarfile.is_tarfile(output_file):
            with tarfile.open(output_file, "r:*") as tar:
                result["valid_archive"] = True
                
                # Iterate through all members to find measurements
                for member in tar.getmembers():
                    if member.isfile() and (member.name.endswith(".plist") or "measure" in member.name.lower()):
                        try:
                            f = tar.extractfile(member)
                            if f:
                                # Try loading as plist
                                try:
                                    data = plistlib.load(f)
                                except Exception:
                                    # Might be binary or other format, skip simple load
                                    continue
                                
                                # Helper to recursively find angular measurements
                                def search_angles(obj):
                                    count = 0
                                    vals = []
                                    
                                    if isinstance(obj, dict):
                                        # InVesalius measurement structure detection
                                        # Look for type indicators
                                        is_angle = False
                                        val = None
                                        
                                        # Check for explicit type field
                                        if "type" in obj and str(obj["type"]).lower() in ["angle", "angular"]:
                                            is_angle = True
                                        
                                        # Check for value field
                                        if "value" in obj:
                                            try:
                                                val = float(obj["value"])
                                            except (ValueError, TypeError):
                                                pass
                                        elif "angle" in obj:
                                            # Some versions store it as 'angle'
                                            try:
                                                val = float(obj["angle"])
                                                is_angle = True # inferred
                                            except (ValueError, TypeError):
                                                pass
                                        
                                        # Check for points count (angles usually have 3 points)
                                        if "points" in obj and isinstance(obj["points"], list):
                                            if len(obj["points"]) == 3:
                                                # Strong hint it's an angle if not explicitly linear
                                                if not is_angle and "distance" not in obj:
                                                    is_angle = True

                                        if is_angle and val is not None:
                                            count += 1
                                            vals.append(val)
                                        
                                        # Recurse
                                        for k, v in obj.items():
                                            c, v_list = search_angles(v)
                                            count += c
                                            vals.extend(v_list)
                                            
                                    elif isinstance(obj, list):
                                        for item in obj:
                                            c, v_list = search_angles(item)
                                            count += c
                                            vals.extend(v_list)
                                    
                                    return count, vals

                                c, v_list = search_angles(data)
                                if c > 0:
                                    result["measurements_found"] = True
                                    result["angular_measurements_count"] += c
                                    result["angle_values"].extend(v_list)
                                    
                        except Exception as e:
                            # print(f"Error processing member {member.name}: {e}")
                            pass
                            
    except Exception as e:
        result["error"] = str(e)

# Validate angle values
result["angle_values"] = [float(v) for v in result["angle_values"]]
result["valid_angle_values_count"] = sum(1 for v in result["angle_values"] if 30.0 <= v <= 170.0)

with open("/tmp/measure_cranial_angle_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="