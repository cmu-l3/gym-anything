#!/bin/bash
echo "=== Exporting subpixel_linear_spectral_unmixing result ==="

# 1. Take final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract telemetry and metadata using Python
python3 << 'PYEOF'
import os
import json

task_start = 0
ts_file = '/tmp/task_start_ts'
if os.path.exists(ts_file):
    with open(ts_file, 'r') as f:
        task_start = int(f.read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'unmix_operator_found': False,
    'endmember_names_found': [],
    'endmember_values_found': [],
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_size_bytes': 0
}

dim_path = '/home/ga/snap_exports/fractional_cover.dim'
tif_path = '/home/ga/snap_exports/fractional_cover.tif'

# Check DIMAP
if os.path.exists(dim_path):
    result['dim_found'] = True
    mtime = int(os.path.getmtime(dim_path))
    if mtime > task_start:
        result['dim_created_after_start'] = True
        
    # Read DIMAP XML to verify provenance (Linear Spectral Unmixing was used)
    try:
        with open(dim_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
            # Look for evidence of Unmixing algorithm in the Processing Graph
            if 'Unmix' in content or 'LinearSpectralUnmixing' in content or 'Endmember' in content:
                result['unmix_operator_found'] = True
            
            # Look for the required endmember names
            for name in ['Vegetation', 'Water', 'Soil']:
                if name in content or name.lower() in content.lower():
                    result['endmember_names_found'].append(name)
            
            # Look for signature values (allowing float conversions like 120.0)
            targets = ['120', '15', '25', '10', '20', '30', '90', '70', '60']
            for val in targets:
                if val in content or f"{val}.0" in content:
                    result['endmember_values_found'].append(val)
    except Exception as e:
        print(f"Error reading DIMAP: {e}")

# Check GeoTIFF
if os.path.exists(tif_path):
    result['tif_found'] = True
    mtime = int(os.path.getmtime(tif_path))
    if mtime > task_start:
        result['tif_created_after_start'] = True
    result['tif_size_bytes'] = os.path.getsize(tif_path)

# Save results for verifier
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export data written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="