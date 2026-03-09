#!/bin/bash
echo "=== Exporting report_mesh_statistics result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence
take_screenshot /tmp/task_end.png

# Paths
STL_FILE="/home/ga/Documents/skull.stl"
REPORT_FILE="/home/ga/Documents/mesh_stats.txt"
TIMESTAMP_FILE="/tmp/task_start_timestamp"
TASK_START=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "0")

# Use Python to analyze both the STL geometry and the text report content
python3 << PYEOF
import struct
import os
import json
import re

stl_path = "$STL_FILE"
report_path = "$REPORT_FILE"
task_start = $TASK_START

result = {
    "stl_exists": False,
    "report_exists": False,
    "stl_stats": {
        "valid_binary": False,
        "triangle_count": 0,
        "file_size": 0,
        "created_during_task": False
    },
    "report_content": {
        "text": "",
        "parsed_triangles": None,
        "parsed_volume": None,
        "parsed_area": None,
        "created_during_task": False
    }
}

# --- Analyze STL ---
if os.path.isfile(stl_path):
    result["stl_exists"] = True
    size = os.path.getsize(stl_path)
    result["stl_stats"]["file_size"] = size
    result["stl_stats"]["created_during_task"] = os.path.getmtime(stl_path) > task_start
    
    # Check Binary STL: 80 bytes header + 4 bytes count + N * 50 bytes data
    # Expected size = 84 + N * 50
    if size >= 84:
        try:
            with open(stl_path, "rb") as f:
                header = f.read(80)
                count_bytes = f.read(4)
                count = struct.unpack("<I", count_bytes)[0]
                expected_size = 84 + (count * 50)
                
                # Allow a small buffer for footer or padding, but standard binary STL is exact
                if size == expected_size:
                    result["stl_stats"]["valid_binary"] = True
                    result["stl_stats"]["triangle_count"] = count
                elif abs(size - expected_size) < 1024:
                     # Soft fail: valid enough for this task if slightly off standard
                    result["stl_stats"]["valid_binary"] = True
                    result["stl_stats"]["triangle_count"] = count
        except Exception as e:
            result["stl_error"] = str(e)

# --- Analyze Report ---
if os.path.isfile(report_path):
    result["report_exists"] = True
    result["report_content"]["created_during_task"] = os.path.getmtime(report_path) > task_start
    try:
        with open(report_path, "r", errors="ignore") as f:
            text = f.read()
            result["report_content"]["text"] = text
            
            # Normalize text for parsing
            norm_text = text.lower().replace(",", "").replace(":", " ")
            
            # Extract numbers associated with keywords
            # Regex looks for "keyword" followed by optional non-digit chars, then a float/int
            
            # Triangles / Faces / Polygons
            tri_match = re.search(r'(triangles?|faces?|polygons?)\D+([0-9]+)', norm_text)
            if tri_match:
                result["report_content"]["parsed_triangles"] = int(tri_match.group(2))
                
            # Volume
            vol_match = re.search(r'(volume)\D+([0-9]+\.?[0-9]*)', norm_text)
            if vol_match:
                result["report_content"]["parsed_volume"] = float(vol_match.group(2))
                
            # Area / Surface
            area_match = re.search(r'(area|surface)\D+([0-9]+\.?[0-9]*)', norm_text)
            if area_match:
                result["report_content"]["parsed_area"] = float(area_match.group(2))
                
    except Exception as e:
        result["report_error"] = str(e)

with open("/tmp/report_mesh_statistics_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="