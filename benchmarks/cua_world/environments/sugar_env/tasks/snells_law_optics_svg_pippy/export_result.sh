#!/bin/bash
echo "=== Exporting snells_law_optics_svg_pippy task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/snells_law_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/snells_law_start_ts 2>/dev/null || echo "0")

# Use Python to robustly parse the output files
python3 << 'PYEOF' > /tmp/snells_law_result.json 2>/dev/null || echo '{"error": "export_script_failed"}' > /tmp/snells_law_result.json
import json
import os
import re
import xml.etree.ElementTree as ET

result = {
    "py_exists": False,
    "py_size": 0,
    "py_modified": False,
    "py_has_trig": False,
    "svg_exists": False,
    "svg_size": 0,
    "svg_modified": False,
    "svg_valid": False,
    "svg_shape_count": 0,
    "has_air": False,
    "has_glass": False,
    "has_45": False,
    "has_27_7": False,
    "error": None
}

py_path = "/home/ga/Documents/snells_law.py"
svg_path = "/home/ga/Documents/refraction.svg"

try:
    with open('/tmp/snells_law_start_ts', 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# Check Python file
if os.path.exists(py_path):
    result["py_exists"] = True
    result["py_size"] = os.path.getsize(py_path)
    if os.path.getmtime(py_path) > task_start:
        result["py_modified"] = True
        
    try:
        with open(py_path, 'r', encoding='utf-8') as f:
            py_content = f.read()
            # Look for trig functions to verify calculations are actually happening
            if 'sin' in py_content and ('asin' in py_content or 'arcsin' in py_content):
                result["py_has_trig"] = True
    except Exception as e:
        pass

# Check SVG file
if os.path.exists(svg_path):
    result["svg_exists"] = True
    result["svg_size"] = os.path.getsize(svg_path)
    if os.path.getmtime(svg_path) > task_start:
        result["svg_modified"] = True
        
    try:
        with open(svg_path, 'r', encoding='utf-8') as f:
            svg_content = f.read()
            
        # Check text contents via regex before rigorous parsing (in case of slight XML errors)
        text_lower = svg_content.lower()
        if 'air' in text_lower: result["has_air"] = True
        if 'glass' in text_lower: result["has_glass"] = True
        if '45' in text_lower: result["has_45"] = True
        
        # Look for the calculated angle: 27.7 degrees (allows 27.72, 27.724, etc.)
        if re.search(r'27\.7\d*', svg_content):
            result["has_27_7"] = True
            
        # Parse XML to count geometric elements
        try:
            # Strip namespaces to make searching easier
            clean_xml = re.sub(r'\sxmlns="[^"]+"', '', svg_content, count=1)
            root = ET.fromstring(clean_xml)
            result["svg_valid"] = True
            
            shapes = 0
            for tag in ['line', 'path', 'polyline', 'polygon']:
                shapes += len(root.findall(f'.//{tag}'))
                shapes += len(root.findall(f'.//{{http://www.w3.org/2000/svg}}{tag}'))
            
            result["svg_shape_count"] = shapes
        except ET.ParseError:
            result["svg_valid"] = False
            
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

chmod 666 /tmp/snells_law_result.json
echo "Result saved to /tmp/snells_law_result.json"
cat /tmp/snells_law_result.json
echo "=== Export complete ==="