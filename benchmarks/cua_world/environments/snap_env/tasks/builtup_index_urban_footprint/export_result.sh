#!/bin/bash
echo "=== Exporting builtup_index_urban_footprint result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Run python script to parse outputs and save result
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
if os.path.exists('/tmp/task_start_ts'):
    with open('/tmp/task_start_ts', 'r') as f:
        task_start = int(f.read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_path': '',
    'dim_mtime': 0,
    'virtual_bands': {},
    'tif_found': False,
    'tif_path': '',
    'tif_size': 0,
    'tif_mtime': 0,
    'txt_found': False,
    'txt_path': '',
    'txt_size': 0,
    'txt_mtime': 0,
    'txt_content': ''
}

# 1. Search for DIMAP output (.dim)
# Expected: /home/ga/snap_projects/urban_analysis.dim
dim_search_dirs = ['/home/ga/snap_projects', '/home/ga/snap_exports', '/home/ga', '/tmp']
for d in dim_search_dirs:
    if not os.path.exists(d): continue
    for root, _, files in os.walk(d):
        for f in files:
            if f.endswith('.dim'):
                full_path = os.path.join(root, f)
                # Skip source files if any were cached
                if 'snap_data' in full_path: continue
                
                mtime = int(os.path.getmtime(full_path))
                if mtime >= task_start:
                    result['dim_found'] = True
                    result['dim_path'] = full_path
                    result['dim_mtime'] = mtime
                    
                    # Parse XML to extract expressions
                    try:
                        tree = ET.parse(full_path)
                        xml_root = tree.getroot()
                        for sbi in xml_root.iter('Spectral_Band_Info'):
                            name_el = sbi.find('BAND_NAME')
                            if name_el is not None and name_el.text:
                                bname = name_el.text.strip()
                                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                                if expr_el is not None and expr_el.text:
                                    result['virtual_bands'][bname.lower()] = expr_el.text.strip()
                    except Exception as e:
                        print(f"Error parsing XML for {full_path}: {e}")
                    break
        if result['dim_found']: break

# 2. Search for GeoTIFF export (.tif)
# Expected: /home/ga/snap_exports/urban_footprint.tif
for d in dim_search_dirs:
    if not os.path.exists(d): continue
    for root, _, files in os.walk(d):
        for f in files:
            if f.lower().endswith(('.tif', '.tiff')):
                full_path = os.path.join(root, f)
                if 'snap_data' in full_path: continue
                
                mtime = int(os.path.getmtime(full_path))
                if mtime >= task_start:
                    size = os.path.getsize(full_path)
                    # Prefer the file actually named urban_footprint or the largest one
                    if 'urban' in f.lower() or size > result['tif_size']:
                        result['tif_found'] = True
                        result['tif_path'] = full_path
                        result['tif_mtime'] = mtime
                        result['tif_size'] = size

# 3. Search for Statistics export (.txt or .csv)
# Expected: /home/ga/snap_exports/bui_statistics.txt
for d in dim_search_dirs:
    if not os.path.exists(d): continue
    for root, _, files in os.walk(d):
        for f in files:
            if f.lower().endswith(('.txt', '.csv')):
                full_path = os.path.join(root, f)
                if 'snap_data' in full_path: continue
                
                mtime = int(os.path.getmtime(full_path))
                if mtime >= task_start:
                    size = os.path.getsize(full_path)
                    if size > 10:
                        try:
                            with open(full_path, 'r', encoding='utf-8', errors='ignore') as text_file:
                                content = text_file.read(1000).lower()
                                # Check if it looks like SNAP statistics output
                                if 'mean' in content or 'sigma' in content or 'minimum' in content:
                                    result['txt_found'] = True
                                    result['txt_path'] = full_path
                                    result['txt_size'] = size
                                    result['txt_mtime'] = mtime
                                    result['txt_content'] = content
                        except Exception as e:
                            print(f"Error reading text file {full_path}: {e}")

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete. Results saved to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="