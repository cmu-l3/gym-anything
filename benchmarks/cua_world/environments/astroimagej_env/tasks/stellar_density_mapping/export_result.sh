#!/bin/bash
echo "=== Exporting Stellar Density Mapping Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

PROJECT_DIR="/home/ga/AstroImages/cluster_density"

# Analyze results using Python
python3 << 'PYEOF'
import json
import os
import glob
import re
import numpy as np

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

PROJECT = "/home/ga/AstroImages/cluster_density"
REPORT_FILE = os.path.join(PROJECT, "density_report.txt")
MAP_FILE = os.path.join(PROJECT, "density_map.tif")

result = {
    "report_found": False,
    "map_found": False,
    "report_content": "",
    "reported_num_stars": None,
    "reported_peak_x": None,
    "reported_peak_y": None,
    "map_width": None,
    "map_height": None,
    "map_max_x": None,
    "map_max_y": None,
    "map_std": None,
    "map_mean": None,
    "map_max_val": None,
    "map_min_val": None
}

if os.path.exists(REPORT_FILE):
    result["report_found"] = True
    with open(REPORT_FILE, "r") as f:
        content = f.read()
    result["report_content"] = content

    # Parse report
    m_stars = re.search(r'num_stars_detected[:\s=]+([0-9]+)', content, re.IGNORECASE)
    if m_stars: result["reported_num_stars"] = int(m_stars.group(1))

    m_x = re.search(r'peak_density_x[:\s=]+([0-9]+)', content, re.IGNORECASE)
    if m_x: result["reported_peak_x"] = int(m_x.group(1))

    m_y = re.search(r'peak_density_y[:\s=]+([0-9]+)', content, re.IGNORECASE)
    if m_y: result["reported_peak_y"] = int(m_y.group(1))

if os.path.exists(MAP_FILE) and HAS_PIL:
    result["map_found"] = True
    try:
        img = Image.open(MAP_FILE)
        img_array = np.array(img).astype(float)
        
        # Handle RGB if saved as such
        if img_array.ndim == 3:
            img_array = np.mean(img_array, axis=2)
            
        result["map_width"] = img_array.shape[1]
        result["map_height"] = img_array.shape[0]
        result["map_mean"] = float(np.mean(img_array))
        result["map_std"] = float(np.std(img_array))
        result["map_max_val"] = float(np.max(img_array))
        result["map_min_val"] = float(np.min(img_array))
        
        peak_y, peak_x = np.unravel_index(np.argmax(img_array), img_array.shape)
        result["map_max_x"] = int(peak_x)
        result["map_max_y"] = int(peak_y)
    except Exception as e:
        result["map_error"] = str(e)

# Write out the results
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export Complete ==="