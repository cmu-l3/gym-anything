#!/bin/bash
echo "=== Exporting masked_spectral_statistics result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Run a Python script to extract product information and verify the text file
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
    'dim_created_after_start': False,
    'masks_found': [],
    'stats_file_found': False,
    'stats_created_after_start': False,
    'stats_file_size': 0,
    'bands_in_stats': 0,
    'mask_applied_in_stats': False,
    'stats_content_snippet': ''
}

# 1. Search for BEAM-DIMAP files
search_dirs = ['/home/ga/snap_exports', '/home/ga/snap_projects', '/home/ga/Desktop', '/home/ga']
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith('.dim') and 'snap_data' not in root:
                    dim_file = os.path.join(root, f)
                    
                    mtime = int(os.path.getmtime(dim_file))
                    if mtime > task_start:
                        result['dim_created_after_start'] = True
                    result['dim_found'] = True
                    
                    try:
                        tree = ET.parse(dim_file)
                        xml_root = tree.getroot()
                        
                        # Look for Mask Definitions
                        for md in xml_root.iter('Mask_Definition'):
                            name_el = md.find('NAME')
                            expr_el = md.find('EXPRESSION')
                            if name_el is not None and expr_el is not None:
                                result['masks_found'].append({
                                    'name': name_el.text.strip() if name_el.text else '',
                                    'expression': expr_el.text.strip() if expr_el.text else ''
                                })
                        
                        # Fallback: Look for Virtual Bands acting as masks
                        for sbi in xml_root.iter('Spectral_Band_Info'):
                            name_el = sbi.find('BAND_NAME')
                            expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                            if name_el is not None and expr_el is not None:
                                if expr_el.text and '>' in expr_el.text:
                                    result['masks_found'].append({
                                        'name': name_el.text.strip() if name_el.text else '',
                                        'expression': expr_el.text.strip()
                                    })
                    except Exception as e:
                        print(f"Error parsing {dim_file}: {e}")

# 2. Search for exported statistics file
for d in search_dirs:
    if os.path.isdir(d):
        for root, dirs, files in os.walk(d):
            for f in files:
                if (f.endswith('.txt') or f.endswith('.csv')) and 'snap_data' not in root:
                    stats_file = os.path.join(root, f)
                    
                    # Heuristic: does the filename suggest statistics?
                    is_stats = 'stat' in f.lower() or 'veg' in f.lower() or 'mask' in f.lower()
                    
                    if is_stats:
                        mtime = int(os.path.getmtime(stats_file))
                        fsize = os.path.getsize(stats_file)
                        
                        if mtime > task_start and fsize > 0:
                            result['stats_file_found'] = True
                            result['stats_created_after_start'] = True
                            result['stats_file_size'] = fsize
                            
                            # Analyze the content
                            try:
                                with open(stats_file, 'r', encoding='utf-8', errors='ignore') as sf:
                                    content = sf.read()
                                    result['stats_content_snippet'] = content[:1000] # Save start for context
                                    
                                    content_lower = content.lower()
                                    
                                    # Count how many distinct bands are represented
                                    band_count = sum(1 for b in ['band_1', 'band_2', 'band_3', 'band_4'] if b in content_lower)
                                    result['bands_in_stats'] = max(result['bands_in_stats'], band_count)
                                    
                                    # Check if a mask was actively applied (SNAP puts ROI mask info in headers)
                                    if 'mask' in content_lower or 'veg' in content_lower or 'roi' in content_lower:
                                        result['mask_applied_in_stats'] = True
                            except Exception as e:
                                print(f"Error reading {stats_file}: {e}")

# Save the extraction to a temporary JSON file
temp_json = '/tmp/task_result_temp.json'
with open(temp_json, 'w') as f:
    json.dump(result, f, indent=2)

# Safely copy to final destination
os.system(f"cp {temp_json} /tmp/task_result.json && chmod 666 /tmp/task_result.json")
PYEOF

echo "Result JSON written to /tmp/task_result.json:"
cat /tmp/task_result.json

echo "=== Export Complete ==="