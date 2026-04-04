#!/bin/bash
# Export script for labeled_particle_map task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Results ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Paths
MAP_PATH="/home/ga/ImageJ_Data/results/labeled_map.png"
CSV_PATH="/home/ga/ImageJ_Data/results/particle_data.csv"
JSON_OUT="/tmp/labeled_map_result.json"
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Python script to analyze artifacts
python3 << PYEOF
import json
import os
import csv
import sys
import numpy as np
from PIL import Image

result = {
    "map_exists": False,
    "map_is_rgb": False,
    "map_width": 0,
    "map_height": 0,
    "csv_exists": False,
    "csv_rows": 0,
    "csv_columns": [],
    "columns_valid": False,
    "files_newly_created": False,
    "task_start_timestamp": $START_TIME
}

# 1. Analyze Map Image
if os.path.exists("$MAP_PATH"):
    result["map_exists"] = True
    try:
        mtime = os.path.getmtime("$MAP_PATH")
        if mtime > result["task_start_timestamp"]:
            result["files_newly_created"] = True
            
        with Image.open("$MAP_PATH") as img:
            result["map_width"] = img.width
            result["map_height"] = img.height
            # Check mode: RGB is expected for flattened overlays
            if img.mode == 'RGB' or img.mode == 'RGBA':
                result["map_is_rgb"] = True
            elif img.mode == 'P': # Palette mode might be used, check palette
                # If palette implies color, we might accept, but Flatten usually produces RGB
                result["map_is_rgb"] = True 
            else:
                # Grayscale/Binary (L, 1) means likely not flattened with labels
                result["map_is_rgb"] = False
    except Exception as e:
        print(f"Error analyzing image: {e}")

# 2. Analyze Data CSV
if os.path.exists("$CSV_PATH"):
    result["csv_exists"] = True
    try:
        mtime = os.path.getmtime("$CSV_PATH")
        # Update timestamp check
        if mtime > result["task_start_timestamp"] and result["map_exists"]:
             result["files_newly_created"] = True # Both must be new ideally
        
        with open("$CSV_PATH", 'r') as f:
            # Handle potential Fiji CSV weirdness (sometimes default Results has no header or specific layout)
            # We assume standard "Save As" from Results table
            sample = f.read(1024)
            f.seek(0)
            has_header = csv.Sniffer().has_header(sample)
            reader = csv.reader(f)
            rows = list(reader)
            
            if rows:
                header = rows[0]
                result["csv_columns"] = header
                result["csv_rows"] = len(rows) - 1 # Subtract header
                
                # Check for required columns partial match
                req = ["Area", "Circ", "Feret"]
                header_str = " ".join(header).lower()
                
                # Check existance of all 3 concepts
                has_area = "area" in header_str
                has_circ = "circ" in header_str
                has_feret = "feret" in header_str
                
                result["columns_valid"] = has_area and has_circ and has_feret
                
    except Exception as e:
        print(f"Error analyzing CSV: {e}")

# Save JSON
with open("$JSON_OUT", "w") as f:
    json.dump(result, f, indent=2)

print("Export analysis complete.")
PYEOF

chmod 666 "$JSON_OUT" 2>/dev/null || true
cat "$JSON_OUT"
echo "=== Export Complete ==="