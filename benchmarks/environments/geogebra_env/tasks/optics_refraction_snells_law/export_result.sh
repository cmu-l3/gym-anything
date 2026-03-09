#!/bin/bash
# Export script for Optics Refraction task
set -o pipefail

# Always create a result file
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "{ \"error\": \"Export script failed\" }" > /tmp/task_result.json
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Helper functions
take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }

echo "=== Exporting Optics Refraction Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Run Python analyzer to parse the GeoGebra file
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/refraction_lab.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_created_during_task": False,
    "sliders_found": [],
    "math_functions_used": [],
    "has_snells_logic": False,
    "geometry_elements": 0,
    "error": None
}

# 1. Find the file
if os.path.exists(EXPECTED_FILE):
    result["file_found"] = True
    mtime = os.path.getmtime(EXPECTED_FILE)
    if mtime > TASK_START_TIME:
        result["file_created_during_task"] = True
    
    # 2. Analyze XML content
    try:
        with zipfile.ZipFile(EXPECTED_FILE, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Check for sliders (numeric elements with animation steps usually, or just numbers)
                # Look for definitions like <element type="numeric" label="n1">
                sliders = []
                if re.search(r'<element type="numeric"[^>]*label="n1"', xml_content):
                    sliders.append("n1")
                if re.search(r'<element type="numeric"[^>]*label="n2"', xml_content):
                    sliders.append("n2")
                result["sliders_found"] = sliders

                # Check for Trigonometry functions (sin, asin/arcsin)
                # GeoGebra stores commands often as <command name=" ... "> or in expression attributes
                math_funcs = []
                if "sin(" in xml_content or "sin " in xml_content:
                    math_funcs.append("sin")
                if "asin(" in xml_content or "asin " in xml_content or "arcsin" in xml_content:
                    math_funcs.append("asin")
                result["math_functions_used"] = math_funcs

                # Check for Snell's Law Logic (n1/n2 ratio inside asin)
                # We look for simple heuristic signatures of the physics logic in expressions
                # e.g. asin( ... n1 ... n2 ... ) or asin( ... n2 ... n1 ... )
                # Simplest check: does 'asin' appear in the file?
                # Stronger check: usage of n1 and n2
                has_logic = False
                if "asin" in math_funcs or "arcsin" in math_funcs:
                    # Logic is likely present if we have sliders and arcsin
                    if len(sliders) >= 2:
                        has_logic = True
                result["has_snells_logic"] = has_logic

                # Count geometry elements (points, lines, segments, rays)
                geo_count = 0
                geo_count += len(re.findall(r'<element type="point"', xml_content))
                geo_count += len(re.findall(r'<element type="line"', xml_content))
                geo_count += len(re.findall(r'<element type="segment"', xml_content))
                geo_count += len(re.findall(r'<element type="ray"', xml_content))
                result["geometry_elements"] = geo_count

    except Exception as e:
        result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete."
cat /tmp/task_result.json