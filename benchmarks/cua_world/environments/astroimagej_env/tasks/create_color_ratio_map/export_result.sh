#!/bin/bash
echo "=== Exporting Color Ratio Map Task Results ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run python extraction script
python3 << 'PYEOF'
import os
import json
import re

res = {
    'map_exists': False,
    'txt_exists': False,
    'map_shape': None,
    'map_median': None,
    'txt_content': '',
    'parsed_stars': {},
    'parsed_bluest': None,
    'parsed_reddest': None,
    'map_mtime': 0,
    'txt_mtime': 0,
    'error': None
}

try:
    import numpy as np
    from astropy.io import fits
    
    agent_map = '/home/ga/AstroImages/color_map/output/BV_ratio_map.fits'
    agent_txt = '/home/ga/AstroImages/color_map/output/color_results.txt'

    if os.path.exists(agent_map):
        res['map_exists'] = True
        res['map_mtime'] = os.path.getmtime(agent_map)
        try:
            data = fits.getdata(agent_map)
            res['map_shape'] = list(data.shape)
            res['map_median'] = float(np.nanmedian(data))
        except Exception as map_err:
            res['error'] = f"Map parsing error: {map_err}"

    if os.path.exists(agent_txt):
        res['txt_exists'] = True
        res['txt_mtime'] = os.path.getmtime(agent_txt)
        with open(agent_txt, 'r') as f:
            content = f.read()
        res['txt_content'] = content[:3000]

        lines = content.split('\n')
        
        # Parse Star values robustly
        for label in ['Star_A', 'Star_B', 'Star_C']:
            for line in lines:
                if label.lower() in line.lower():
                    # Find all floats
                    nums = re.findall(r'[0-9]+\.[0-9]+', line)
                    if not nums:
                        # Fallback to integer formats
                        nums = re.findall(r'\b[0-9]+\b', line)
                    if nums:
                        # Assume the last number in the line is the measurement (not the coordinates)
                        res['parsed_stars'][label] = float(nums[-1])
                    break
                    
        # Parse Bluest/Reddest identifications
        for line in lines:
            if 'bluest' in line.lower():
                m = re.search(r'star_([abc])', line, re.IGNORECASE)
                if m: res['parsed_bluest'] = f"Star_{m.group(1).upper()}"
            if 'reddest' in line.lower():
                m = re.search(r'star_([abc])', line, re.IGNORECASE)
                if m: res['parsed_reddest'] = f"Star_{m.group(1).upper()}"

except Exception as e:
    res['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(res, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="