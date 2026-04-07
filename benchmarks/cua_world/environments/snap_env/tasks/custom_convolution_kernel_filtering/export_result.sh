#!/bin/bash
echo "=== Exporting custom_convolution_kernel_filtering result ==="

if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_end.png
else
    DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true
fi

# Run a Python script inside the container to safely parse XML and file states
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

task_start_file = '/tmp/task_start_ts'
task_start = int(open(task_start_file).read().strip()) if os.path.exists(task_start_file) else 0

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'tif_found': False,
    'tif_created_after_start': False,
    'kernel_found': False,
    'kernel_weights': [],
    'matrix_matches': False
}

target_weights = [-1.0, -2.0, -1.0, -2.0, 12.0, -2.0, -1.0, -2.0, -1.0]

search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']

# 1. Search for .dim files and parse kernel
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim') and 'snap_data' not in root:
                    full_path = os.path.join(root, f)
                    mtime = int(os.path.getmtime(full_path))
                    
                    if mtime > task_start:
                        result['dim_found'] = True
                        result['dim_created_after_start'] = True
                        
                        try:
                            tree = ET.parse(full_path)
                            # Locate the <kernel> tag inside <Filter_Band_Info>
                            for kernel in tree.iter('kernel'):
                                result['kernel_found'] = True
                                weights = []
                                for w in kernel.findall('weight'):
                                    weights.append(float(w.text))
                                
                                result['kernel_weights'] = weights
                                
                                # Verify strict math parameters
                                if len(weights) == 9:
                                    match = all(abs(w - t) < 0.01 for w, t in zip(weights, target_weights))
                                    if match:
                                        result['matrix_matches'] = True
                        except Exception as e:
                            print(f"Error parsing {full_path}: {e}")

# 2. Search for GeoTIFF export
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.lower().endswith(('.tif', '.tiff')) and 'snap_data' not in root:
                    full_path = os.path.join(root, f)
                    mtime = int(os.path.getmtime(full_path))
                    
                    if mtime > task_start:
                        result['tif_found'] = True
                        result['tif_created_after_start'] = True

# Write state for host verification
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON Exported:"
cat /tmp/task_result.json
echo "=== Export Complete ==="