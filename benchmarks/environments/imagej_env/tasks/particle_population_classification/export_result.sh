#!/bin/bash
# Export script for Particle Population Classification task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Classification Results ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Python script to parse CSVs and validate outputs
python3 << 'PYEOF'
import json
import csv
import os
import sys

results_dir = "/home/ga/ImageJ_Data/results"
task_start_file = "/tmp/task_start_timestamp"
output_file = "/tmp/particle_classification_result.json"

output = {
    "small_csv": {"exists": False, "count": 0, "min_area": 0, "max_area": 0, "created_during_task": False},
    "large_csv": {"exists": False, "count": 0, "min_area": 0, "max_area": 0, "created_during_task": False},
    "map_image": {"exists": False, "created_during_task": False},
    "task_start_timestamp": 0
}

# Get task start time
try:
    with open(task_start_file, 'r') as f:
        output["task_start_timestamp"] = int(f.read().strip())
except:
    pass

def analyze_csv(filename, key):
    filepath = os.path.join(results_dir, filename)
    if os.path.exists(filepath):
        output[key]["exists"] = True
        
        # Check timestamp
        mtime = int(os.path.getmtime(filepath))
        if mtime > output["task_start_timestamp"]:
            output[key]["created_during_task"] = True
            
        # Parse content
        try:
            with open(filepath, 'r') as f:
                reader = csv.DictReader(f)
                areas = []
                for row in reader:
                    # Look for 'Area' column (case insensitive)
                    for k, v in row.items():
                        if k and 'area' in k.lower():
                            try:
                                areas.append(float(v))
                                break
                            except:
                                pass
                
                output[key]["count"] = len(areas)
                if areas:
                    output[key]["min_area"] = min(areas)
                    output[key]["max_area"] = max(areas)
        except Exception as e:
            print(f"Error parsing {filename}: {e}")

# Analyze CSVs
analyze_csv("small_particles.csv", "small_csv")
analyze_csv("large_particles.csv", "large_csv")

# Check Map Image
map_path = os.path.join(results_dir, "classification_map.png")
if os.path.exists(map_path):
    output["map_image"]["exists"] = True
    if int(os.path.getmtime(map_path)) > output["task_start_timestamp"]:
        output["map_image"]["created_during_task"] = True

# Write result
with open(output_file, 'w') as f:
    json.dump(output, f, indent=2)

print("Export logic completed.")
PYEOF

echo "Result JSON generated at /tmp/particle_classification_result.json"
cat /tmp/particle_classification_result.json