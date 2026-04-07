#!/bin/bash
echo "=== Exporting drought_index_correlative_analysis result ==="

# Source utility functions if available
if [ -f /workspace/utils/task_utils.sh ]; then
    source /workspace/utils/task_utils.sh
else
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# Take final screenshot
take_screenshot /tmp/drought_analysis_end_screenshot.png

# Run Python script to parse results safely
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

# Load task start time
task_start = 0
ts_file = '/tmp/drought_analysis_start_ts'
if os.path.exists(ts_file):
    try:
        task_start = int(open(ts_file).read().strip())
    except ValueError:
        pass

result = {
    'task_start': task_start,
    'dim_found': False,
    'dim_created_after_start': False,
    'ndvi_band_found': False,
    'ndvi_expression': '',
    'plot_found': False,
    'plot_created_after_start': False,
    'plot_size_bytes': 0,
    'stats_found': False,
    'stats_created_after_start': False,
    'stats_content': ''
}

search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']

# 1. Look for DIMAP product and verify NDVI expression
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim'):
                    full_path = os.path.join(root, f)
                    if 'snap_data' in full_path:
                        continue
                    
                    try:
                        mtime = int(os.path.getmtime(full_path))
                        if mtime > task_start:
                            result['dim_created_after_start'] = True
                        result['dim_found'] = True

                        tree = ET.parse(full_path)
                        xml_root = tree.getroot()

                        for sbi in xml_root.iter('Spectral_Band_Info'):
                            name_el = sbi.find('BAND_NAME')
                            if name_el is not None and name_el.text:
                                bname = name_el.text.strip().lower()
                                if 'ndvi' in bname:
                                    result['ndvi_band_found'] = True
                                    expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                                    if expr_el is not None and expr_el.text:
                                        result['ndvi_expression'] = expr_el.text.strip()
                    except Exception as e:
                        print(f"Error parsing DIMAP {full_path}: {e}")

# 2. Look for Plot Image (PNG/JPEG)
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.lower().endswith(('.png', '.jpg', '.jpeg')):
                    full_path = os.path.join(root, f)
                    if 'snap_data' in full_path or 'screenshot' in full_path:
                        continue
                    
                    try:
                        fsize = os.path.getsize(full_path)
                        mtime = int(os.path.getmtime(full_path))
                        
                        # Use the most recently modified non-trivial image
                        if mtime > task_start and fsize > 1024:
                            if mtime > result.get('_plot_mtime', 0):
                                result['plot_found'] = True
                                result['plot_created_after_start'] = True
                                result['plot_size_bytes'] = fsize
                                result['_plot_mtime'] = mtime
                    except Exception:
                        pass

# 3. Look for Stats data (TXT/CSV)
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.lower().endswith(('.txt', '.csv')):
                    full_path = os.path.join(root, f)
                    if 'snap_data' in full_path:
                        continue
                    
                    try:
                        mtime = int(os.path.getmtime(full_path))
                        if mtime > task_start:
                            with open(full_path, 'r', encoding='utf-8', errors='ignore') as text_file:
                                content = text_file.read()
                                # Only grab files that look like SNAP correlative or general stats output
                                content_lower = content.lower()
                                if 'regression' in content_lower or 'correlation' in content_lower or 'ndvi' in content_lower or 'band_1' in content_lower:
                                    result['stats_found'] = True
                                    result['stats_created_after_start'] = True
                                    # Truncate content so JSON doesn't explode if they exported raw data points
                                    result['stats_content'] = content[:2000]
                    except Exception:
                        pass

# Cleanup temp keys
if '_plot_mtime' in result:
    del result['_plot_mtime']

# Write JSON result
with open('/tmp/drought_index_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/drought_index_result.json")
PYEOF

echo "=== Export Complete ==="