#!/bin/bash
echo "=== Exporting radiometric_quantization_error_assessment result ==="

DISPLAY=:1 scrot /tmp/quantization_end_screenshot.png 2>/dev/null || true

python3 << 'PYEOF'
import os, json, xml.etree.ElementTree as ET

task_start = 0
ts_file = '/tmp/quantization_task_start_ts'
if os.path.exists(ts_file):
    task_start = int(open(ts_file).read().strip())

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'bands': {},
    'tif_found': False,
    'tif_created_after_start': False,
    'tif_file_size': 0
}

dim_files = []
for d in ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga', '/tmp']:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim'):
                    full = os.path.join(root, f)
                    if 'snap_data' not in full:
                        dim_files.append(full)

dim_files = list(set(dim_files))

for dim_file in dim_files:
    try:
        mtime = int(os.path.getmtime(dim_file))
        if mtime > task_start:
            result['dim_created_after_start'] = True
        result['dim_found'] = True
        
        tree = ET.parse(dim_file)
        root = tree.getroot()
        
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                dtype = ''
                expr = ''
                
                dt_el = sbi.find('DATA_TYPE')
                if dt_el is not None and dt_el.text:
                    dtype = dt_el.text.strip()
                
                expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                if expr_el is not None and expr_el.text:
                    expr = expr_el.text.strip()
                    
                result['bands'][bname] = {
                    'data_type': dtype,
                    'expression': expr
                }
    except Exception as e:
        print(f"Error parsing {dim_file}: {e}")

# Check GeoTIFF
tif_dirs = ['/home/ga/snap_exports', '/home/ga/Desktop', '/home/ga']
for d in tif_dirs:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.lower().endswith(('.tif', '.tiff')):
                full = os.path.join(d, f)
                if 'snap_data' in full:
                    continue
                fsize = os.path.getsize(full)
                mtime = int(os.path.getmtime(full))
                if mtime > task_start and fsize > result['tif_file_size']:
                    result['tif_found'] = True
                    result['tif_created_after_start'] = True
                    result['tif_file_size'] = fsize

# Save to temp file and move to avoid permissions issues
with open('/tmp/quantization_result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)

os.system('cp /tmp/quantization_result_temp.json /tmp/quantization_result.json')
os.system('chmod 666 /tmp/quantization_result.json')
PYEOF

echo "Result written to /tmp/quantization_result.json"
cat /tmp/quantization_result.json
echo "=== Export Complete ==="