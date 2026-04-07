#!/bin/bash
echo "=== Exporting dl_radiometric_scaling_uint8 result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import os
import json
import glob
import xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/dl_task_start_ts'
if os.path.exists(ts_file):
    with open(ts_file) as f:
        task_start = int(f.read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'dim_band_count': 0,
    'dim_data_types': [],
    'dim_scaling_formulas': [],
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0,
    'valid_scaling_data': False
}

# 1. Search for BEAM-DIMAP outputs
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga', '/tmp']
dim_files = []
for d in search_dirs:
    if os.path.isdir(d):
        for root_dir, _, files in os.walk(d):
            if 'snap_data' in root_dir: continue
            for f in files:
                if f.endswith('.dim'):
                    dim_files.append(os.path.join(root_dir, f))

best_dim = None
for dim_file in dim_files:
    if int(os.path.getmtime(dim_file)) > task_start:
        best_dim = dim_file
        break
if not best_dim and dim_files:
    best_dim = dim_files[0]

if best_dim:
    result['dim_found'] = True
    if int(os.path.getmtime(best_dim)) > task_start:
        result['dim_created_after_start'] = True
    try:
        tree = ET.parse(best_dim)
        root = tree.getroot()
        bands = list(root.iter('Spectral_Band_Info'))
        result['dim_band_count'] = len(bands)
        
        for b in bands:
            for child in b:
                if child.tag.lower() == 'data_type':
                    if child.text:
                        result['dim_data_types'].append(child.text.strip().lower())
                elif child.tag.lower() == 'virtual_band_expression':
                    if child.text:
                        result['dim_scaling_formulas'].append(child.text.strip().lower())

        # Check raw .img data inside the .data directory for valid scaling bounds (0-255)
        data_dir = best_dim.replace('.dim', '.data')
        if os.path.isdir(data_dir):
            img_files = glob.glob(os.path.join(data_dir, '*.img'))
            for img_path in img_files:
                with open(img_path, 'rb') as f:
                    data = f.read(1024 * 1024) # Evaluate up to 1MB sample
                    if len(data) > 0:
                        sampled = data[::10]  # Sample every 10th byte for speed
                        mean_val = sum(sampled) / len(sampled)
                        # A properly scaled 8-bit optical image typically has a mean comfortably within [5, 240]
                        if 5 < mean_val < 250:
                            result['valid_scaling_data'] = True
    except Exception as e:
        print(f"Error parsing DIMAP XML: {e}")

# 2. Search for GeoTIFF exports
for d in search_dirs:
    if os.path.isdir(d):
        for root_dir, _, files in os.walk(d):
            if 'snap_data' in root_dir: continue
            for f in files:
                if f.lower().endswith(('.tif', '.tiff')):
                    full = os.path.join(root_dir, f)
                    if int(os.path.getmtime(full)) > task_start:
                        result['tif_found'] = True
                        result['tif_created_after_start'] = True
                        result['tif_file_size'] = os.path.getsize(full)
                        break
            if result['tif_found']: break
    if result['tif_found']: break

# Save result payload safely
out_json = '/tmp/dl_radiometric_scaling_result.json'
with open(out_json, 'w') as f:
    json.dump(result, f, indent=2)

os.system(f"chmod 666 {out_json} 2>/dev/null || true")
PYEOF

echo "Result JSON saved to /tmp/dl_radiometric_scaling_result.json"
echo "=== Export Complete ==="