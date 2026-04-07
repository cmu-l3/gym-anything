#!/bin/bash
echo "=== Exporting feature_space_scatter_plot_subset result ==="

# Take final state screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Run python script to collect and structure data securely
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

# Retrieve task start timestamp
task_start = 0
if os.path.exists('/tmp/task_start_ts'):
    with open('/tmp/task_start_ts', 'r') as f:
        task_start = int(f.read().strip())

result = {
    "task_start_ts": task_start,
    "dim_file_exists": False,
    "dim_file_mtime": 0,
    "raster_width": 0,
    "raster_height": 0,
    "scatter_export_exists": False,
    "scatter_export_size": 0,
    "scatter_export_mtime": 0,
    "scatter_export_name": ""
}

# 1. Parse subset XML to extract real dimensions
dim_path = "/home/ga/snap_projects/farm_subset.dim"
if os.path.exists(dim_path):
    result["dim_file_exists"] = True
    result["dim_file_mtime"] = int(os.path.getmtime(dim_path))
    try:
        tree = ET.parse(dim_path)
        root = tree.getroot()
        width_el = root.find(".//Raster_Dimensions/WIDTH")
        height_el = root.find(".//Raster_Dimensions/HEIGHT")
        if width_el is not None and width_el.text:
            result["raster_width"] = int(width_el.text)
        if height_el is not None and height_el.text:
            result["raster_height"] = int(height_el.text)
    except Exception as e:
        print(f"Error parsing DIMAP XML: {e}")

# 2. Check for scatter plot export presence and legitimacy
export_dir = "/home/ga/snap_exports"
if os.path.exists(export_dir):
    for file in os.listdir(export_dir):
        if file.startswith("red_nir_scatter"):
            file_path = os.path.join(export_dir, file)
            result["scatter_export_exists"] = True
            result["scatter_export_name"] = file
            result["scatter_export_size"] = os.path.getsize(file_path)
            result["scatter_export_mtime"] = int(os.path.getmtime(file_path))
            break  # Process the first matching valid prefix

# Write result payload for verifier consumption
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

# Ensure file permissions allow the verifier process to read it
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Data collection complete. Result payload:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="