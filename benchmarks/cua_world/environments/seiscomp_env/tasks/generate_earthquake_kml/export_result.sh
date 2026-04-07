#!/bin/bash
echo "=== Exporting generate_earthquake_kml result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
KML_PATH="/home/ga/earthquake_catalog.kml"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# We will use Python to safely parse the KML and verify it against the ground truth
# This prevents bash parsing errors and allows robust regex/XML checking.

python3 << PYEOF
import os
import json
import re
import xml.etree.ElementTree as ET

result = {
    "task_start": int("$TASK_START"),
    "task_end": int("$TASK_END"),
    "file_exists": False,
    "file_size_bytes": 0,
    "created_during_task": False,
    "valid_xml": False,
    "has_kml_structure": False,
    "coords_present": False,
    "coords_accurate": False,
    "mag_present": False,
    "mag_accurate": False,
    "depth_present": False,
    "time_present": False,
    "doc_name_present": False
}

kml_path = "$KML_PATH"

try:
    with open('/tmp/ground_truth.json', 'r') as f:
        gt = json.load(f)
except Exception as e:
    gt = {"lat": 0, "lon": 0, "depth": 0, "mag": 0, "time": ""}

if os.path.exists(kml_path):
    result["file_exists"] = True
    stat = os.stat(kml_path)
    result["file_size_bytes"] = stat.st_size
    
    if stat.st_mtime >= result["task_start"]:
        result["created_during_task"] = True
        
    try:
        with open(kml_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
        # 1. XML Validity and Structure
        try:
            root = ET.fromstring(content)
            result["valid_xml"] = True
            
            # Remove namespaces for easier checking
            tags = [elem.tag.split('}')[-1].lower() if '}' in elem.tag else elem.tag.lower() for elem in root.iter()]
            
            has_kml = 'kml' in root.tag.lower()
            has_doc = 'document' in tags
            has_pm = 'placemark' in tags
            
            if has_kml and has_doc and has_pm:
                result["has_kml_structure"] = True
                
            # Check for document name
            for elem in root.iter():
                tag = elem.tag.split('}')[-1].lower() if '}' in elem.tag else elem.tag.lower()
                if tag == 'name' and elem.text and 'seiscomp' in elem.text.lower():
                    result["doc_name_present"] = True
                    break
        except Exception as xml_err:
            pass # Not valid XML, but we can still regex the text for partial credit
            
        # 2. Coordinates extraction (KML uses lon,lat)
        coord_pattern = r'[-+]?\d+\.\d+\s*,\s*[-+]?\d+\.\d+'
        coords_found = re.findall(coord_pattern, content)
        
        if coords_found:
            result["coords_present"] = True
            
            for coord in coords_found:
                parts = coord.split(',')
                if len(parts) >= 2:
                    try:
                        c1 = float(parts[0].strip())
                        c2 = float(parts[1].strip())
                        
                        gt_lat = float(gt["lat"])
                        gt_lon = float(gt["lon"])
                        
                        # Accept either lon,lat or lat,lon as long as they are close to GT
                        if (abs(c1 - gt_lon) < 0.5 and abs(c2 - gt_lat) < 0.5) or \
                           (abs(c1 - gt_lat) < 0.5 and abs(c2 - gt_lon) < 0.5):
                            result["coords_accurate"] = True
                            break
                    except ValueError:
                        pass
                        
        # 3. Magnitude extraction
        gt_mag = float(gt["mag"])
        all_numbers = re.findall(r'(\d+\.\d+)', content)
        
        for num_str in all_numbers:
            try:
                num = float(num_str)
                if abs(num - gt_mag) < 0.3:
                    result["mag_present"] = True
                    result["mag_accurate"] = True
                    break
            except ValueError:
                pass
                
        # 4. Depth extraction
        gt_depth = float(gt["depth"])
        depth_pattern = re.findall(r'[Dd]epth.*?(\d+\.?\d*)', content)
        if depth_pattern:
            for d in depth_pattern:
                try:
                    if abs(float(d) - gt_depth) < 50:
                        result["depth_present"] = True
                        break
                except ValueError:
                    pass
                    
        # Fallback for depth if not explicitly labelled but a number matches
        if not result["depth_present"]:
            for num_str in all_numbers:
                try:
                    num = float(num_str)
                    if abs(num - gt_depth) < 50 and num > 3.0: # Distinguish from mag
                        result["depth_present"] = True
                        break
                except ValueError:
                    pass
                    
        # 5. Time extraction (ISO 8601)
        iso_pattern = r'\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}'
        if re.search(iso_pattern, content):
            result["time_present"] = True

except Exception as e:
    result["error"] = str(e)

# Write result to temp JSON
import tempfile, shutil
fd, path = tempfile.mkstemp(suffix=".json")
with os.fdopen(fd, 'w') as f:
    json.dump(result, f, indent=4)
shutil.move(path, "/tmp/task_result.json")
os.chmod("/tmp/task_result.json", 0o666)
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="