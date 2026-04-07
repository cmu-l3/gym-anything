#!/bin/bash
echo "=== Exporting Streptavidin-Biotin Stereo Visualization Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before doing anything else
take_screenshot /tmp/streptavidin_end_screenshot.png

# Collect result data using a Python heredoc (avoids tricky bash parsing for binary data)
python3 << 'PYEOF'
import json
import os
import struct

try:
    with open("/tmp/streptavidin_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/streptavidin_stereo.png"
report_path = "/home/ga/PyMOL_Data/streptavidin_pocket.txt"

result = {
    "figure_exists": False,
    "figure_size_bytes": 0,
    "figure_is_new": False,
    "figure_width": 0,
    "figure_height": 0,
    "report_exists": False,
    "report_content": ""
}

# 1. Figure Check & Image Dimension Extraction
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
    
    # Extract PNG dimensions using struct (no PIL dependency required)
    try:
        with open(fig_path, 'rb') as f:
            head = f.read(24)
            if head.startswith(b'\x89PNG\r\n\x1a\n'):
                # Width and Height are standard at bytes 16-24 in the IHDR chunk
                w, h = struct.unpack('>LL', head[16:24])
                result["figure_width"] = w
                result["figure_height"] = h
    except Exception as e:
        print(f"Error reading PNG dims: {e}")

# 2. Report Check
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()

# Write JSON out
with open("/tmp/streptavidin_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/streptavidin_result.json")
PYEOF

echo "=== Export Complete ==="