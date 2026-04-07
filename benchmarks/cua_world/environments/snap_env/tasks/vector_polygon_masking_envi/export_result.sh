#!/bin/bash
echo "=== Exporting vector_polygon_masking_envi result ==="

# Capture the final screen state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract ENVI files and calculate valid pixel ratio using Python
python3 << 'PYEOF'
import os, json, glob
import numpy as np

task_start = 0
if os.path.exists('/tmp/task_start_ts'):
    with open('/tmp/task_start_ts') as f:
        task_start = int(f.read().strip())

result = {
    'task_start': task_start,
    'envi_found': False,
    'envi_created_after_start': False,
    'band_count': 0,
    'total_pixels': 0,
    'valid_pixels': 0,
    'masking_ratio': 1.0,
    'envi_file': ''
}

# Find all ENVI header files in the export directory
hdr_files = glob.glob('/home/ga/snap_exports/*.hdr')
if hdr_files:
    hdr_file = hdr_files[0]
    mtime = int(os.path.getmtime(hdr_file))
    if mtime > task_start:
        result['envi_created_after_start'] = True
    
    result['envi_found'] = True
    result['envi_file'] = os.path.basename(hdr_file)
    
    # Parse ENVI header metadata
    metadata = {}
    with open(hdr_file, 'r') as f:
        for line in f:
            if '=' in line:
                k, v = line.split('=', 1)
                metadata[k.strip().lower()] = v.strip()
    
    lines = int(metadata.get('lines', 0))
    samples = int(metadata.get('samples', 0))
    bands = int(metadata.get('bands', 0))
    data_type = int(metadata.get('data type', 4))
    
    result['band_count'] = bands
    result['total_pixels'] = lines * samples
    
    # Locate the accompanying binary data file
    base = os.path.splitext(hdr_file)[0]
    data_file = None
    for ext in ['.img', '.data', '']:
        if os.path.exists(base + ext) and os.path.isfile(base + ext):
            data_file = base + ext
            break
            
    if data_file and bands > 0 and lines > 0 and samples > 0:
        # Standard ENVI numerical type mapping
        dtype_map = {1: np.uint8, 2: np.int16, 3: np.int32, 4: np.float32, 5: np.float64, 12: np.uint16}
        dt = dtype_map.get(data_type, np.float32)
        try:
            # Load binary array. Note: For accurate masking ratio, analyzing the entire array length is robust 
            # regardless of interleave type (BSQ, BIL, BIP), since identical masking is applied across all bands.
            arr = np.fromfile(data_file, dtype=dt)
            if len(arr) > 0:
                if np.issubdtype(dt, np.floating):
                    valid = np.count_nonzero(~np.isnan(arr) & (arr > 0))
                else:
                    valid = np.count_nonzero(arr > 0)
                
                result['valid_pixels'] = int(valid)
                result['masking_ratio'] = float(valid) / len(arr)
        except Exception as e:
            print("Error reading binary data:", e)

with open('/tmp/vector_masking_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/vector_masking_result.json 2>/dev/null || true
echo "=== Export Complete ==="