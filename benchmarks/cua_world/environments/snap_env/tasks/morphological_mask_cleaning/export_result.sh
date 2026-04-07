#!/bin/bash
echo "=== Exporting morphological_mask_cleaning result ==="

# Capture final visual state
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Extract results directly from the ENVI binary formats inside the DIMAP .data folder
# This parses the physical files to do rigorous mathematical proofs on the matrices
python3 << 'PYEOF'
import os, json, re
import numpy as np

result = {
    'task_start': 0,
    'dim_found': False,
    'dim_created_after_start': False,
    'bands_found': [],
    'binary_integrity': True,
    'sums': {},
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_size': 0
}

ts_file = '/tmp/task_start_ts'
if os.path.exists(ts_file):
    result['task_start'] = int(open(ts_file).read().strip())

def read_envi_sum(hdr_path, img_path):
    try:
        with open(hdr_path, 'r') as f:
            content = f.read()
        dt_match = re.search(r'data type\s*=\s*(\d+)', content)
        if not dt_match: return None, False
        
        dt = int(dt_match.group(1))
        dtype_map = {1: np.uint8, 2: np.int16, 3: np.int32, 4: np.float32, 5: np.float64, 12: np.uint16, 13: np.uint32}
        if dt not in dtype_map: return None, False
        
        arr = np.fromfile(img_path, dtype=dtype_map[dt])
        valid = arr[~np.isnan(arr)] if np.issubdtype(arr.dtype, np.floating) else arr
        
        # Check binary integrity (are elements only 0 or 1?)
        unique_vals = np.unique(valid)
        is_binary = True
        for v in unique_vals:
            if v not in [0, 1]:
                is_binary = False
                
        return float(np.sum(valid)), is_binary
    except Exception as e:
        print(f"Error reading {img_path}: {e}")
        return None, False

search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']
target_bands = ['initial_mask', 'eroded_mask', 'cleaned_mask']

# Look for DIMAP files (.dim)
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim') and 'snap_data' not in root:
                    dim_path = os.path.join(root, f)
                    mtime = int(os.path.getmtime(dim_path))
                    if mtime > result['task_start']:
                        result['dim_created_after_start'] = True
                    result['dim_found'] = True

                    data_dir = dim_path.replace('.dim', '.data')
                    if os.path.isdir(data_dir):
                        for b in target_bands:
                            hdr_path = os.path.join(data_dir, f"{b}.hdr")
                            img_path = os.path.join(data_dir, f"{b}.img")
                            if os.path.exists(hdr_path) and os.path.exists(img_path):
                                if b not in result['bands_found']:
                                    result['bands_found'].append(b)
                                val, is_bin = read_envi_sum(hdr_path, img_path)
                                if val is not None:
                                    result['sums'][b] = val
                                    if not is_bin:
                                        result['binary_integrity'] = False

if len(result['bands_found']) == 0:
    result['binary_integrity'] = False

# Search for GeoTIFF
for d in search_dirs:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.lower().endswith(('.tif', '.tiff')) and 'snap_data' not in f:
                full = os.path.join(d, f)
                fsize = os.path.getsize(full)
                mtime = int(os.path.getmtime(full))
                if mtime > result['task_start'] and fsize > result['tif_size']:
                    result['tif_found'] = True
                    result['tif_created_after_start'] = True
                    result['tif_size'] = fsize

with open('/tmp/morphological_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Saved parsing analysis to /tmp/morphological_result.json")
PYEOF

echo "=== Export Complete ==="