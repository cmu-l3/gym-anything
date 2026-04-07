#!/bin/bash
echo "=== Exporting log_range_compression_ml_prep results ==="

# 1. Take final screenshot of the agent's work
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# 2. Use a Python script to deeply inspect the SNAP XML definitions and file system
#    to gather evidence for programmatic verification.
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

# Read task start time
task_start = 0
try:
    with open('/tmp/task_start_ts', 'r') as f:
        task_start = int(f.read().strip())
except Exception as e:
    print(f"Warning: could not read task_start_ts: {e}")

result = {
    "task_start": task_start,
    "dim_files": [],
    "tif_files": []
}

search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']

# Find and parse DIMAP (.dim) product files
for d in search_dirs:
    if not os.path.exists(d): continue
    for root, dirs, files in os.walk(d):
        for f in files:
            if f.endswith('.dim') and 'snap_data' not in root:
                full_path = os.path.join(root, f)
                try:
                    mtime = int(os.path.getmtime(full_path))
                    tree = ET.parse(full_path)
                    xml_root = tree.getroot()
                    
                    vbands = {}
                    # Extract Virtual Band expressions
                    for sbi in xml_root.iter('Spectral_Band_Info'):
                        name_el = sbi.find('BAND_NAME')
                        expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                        if name_el is not None and expr_el is not None and expr_el.text:
                            vbands[name_el.text.strip()] = expr_el.text.strip()
                    
                    result["dim_files"].append({
                        "path": full_path,
                        "created_after_start": mtime > task_start,
                        "virtual_bands": vbands
                    })
                except Exception as e:
                    print(f"Error parsing {full_path}: {e}")

# Find GeoTIFF (.tif) exports
for d in search_dirs:
    if not os.path.exists(d): continue
    for root, dirs, files in os.walk(d):
        for f in files:
            if f.lower().endswith(('.tif', '.tiff')) and 'snap_data' not in root:
                full_path = os.path.join(root, f)
                try:
                    mtime = int(os.path.getmtime(full_path))
                    size = os.path.getsize(full_path)
                    result["tif_files"].append({
                        "path": full_path,
                        "created_after_start": mtime > task_start,
                        "size": size
                    })
                except Exception as e:
                    print(f"Error reading {full_path}: {e}")

# Save the evidence to a JSON file for the verifier
output_json = '/tmp/task_result.json'
with open(output_json, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported results to {output_json}")
PYEOF

echo "=== Export Complete ==="