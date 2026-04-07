#!/bin/bash
echo "=== Exporting mineral_ratio_composite result ==="

# Capture final screenshot for VLM verification
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Run Python script to parse the output files and create a structured JSON report
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

# Read task start time
task_start = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    pass

export_dir = "/home/ga/snap_exports"
result = {
    "task_start_time": task_start,
    "dimap_found": False,
    "dimap_created_during_task": False,
    "total_bands": 0,
    "division_expressions": 0,
    "ratio_bands_named": 0,
    "band_names": [],
    "geotiff_found": False,
    "geotiff_created_during_task": False,
    "geotiff_size_bytes": 0,
    "snap_running": False
}

# 1. Check if SNAP is still running
snap_running = os.system("pgrep -f org.esa.snap > /dev/null") == 0
result["snap_running"] = snap_running

# 2. Check DIMAP Output
dimap_path = os.path.join(export_dir, "mineral_ratios.dim")
if not os.path.exists(dimap_path):
    # Try finding any dimap file in the directory
    for f in os.listdir(export_dir) if os.path.exists(export_dir) else []:
        if f.endswith(".dim"):
            dimap_path = os.path.join(export_dir, f)
            break

if os.path.exists(dimap_path):
    result["dimap_found"] = True
    mtime = int(os.path.getmtime(dimap_path))
    if mtime > task_start:
        result["dimap_created_during_task"] = True
    
    # Parse DIMAP XML
    try:
        tree = ET.parse(dimap_path)
        root = tree.getroot()
        
        bands = []
        division_count = 0
        ratio_names_found = 0
        
        # Look for band information
        for sbi in root.iter('Spectral_Band_Info'):
            # Count bands and get names
            name_elem = sbi.find('BAND_NAME')
            if name_elem is not None and name_elem.text:
                bname = name_elem.text.strip()
                bands.append(bname)
                
                # Check for descriptive names
                bl = bname.lower()
                if any(x in bl for x in ['ratio', 'fe', 'clay', 'hydroxyl', 'swir', 'nir', 'red']):
                    ratio_names_found += 1
            
            # Count division expressions
            expr_elem = sbi.find('VIRTUAL_BAND_EXPRESSION')
            if expr_elem is not None and expr_elem.text:
                if '/' in expr_elem.text:
                    division_count += 1
        
        result["total_bands"] = len(bands)
        result["band_names"] = bands
        result["division_expressions"] = division_count
        result["ratio_bands_named"] = ratio_names_found
        
    except Exception as e:
        print(f"Error parsing XML: {e}")

# 3. Check GeoTIFF Output
tiff_path = os.path.join(export_dir, "mineral_ratios.tif")
if not os.path.exists(tiff_path):
    # Try finding any tiff file in the directory
    for f in os.listdir(export_dir) if os.path.exists(export_dir) else []:
        if f.endswith(".tif") or f.endswith(".tiff"):
            tiff_path = os.path.join(export_dir, f)
            break

if os.path.exists(tiff_path):
    result["geotiff_found"] = True
    mtime = int(os.path.getmtime(tiff_path))
    if mtime > task_start:
        result["geotiff_created_during_task"] = True
    result["geotiff_size_bytes"] = os.path.getsize(tiff_path)

# Save result to JSON file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Exported JSON summary:"
cat /tmp/task_result.json
echo "=== Export complete ==="