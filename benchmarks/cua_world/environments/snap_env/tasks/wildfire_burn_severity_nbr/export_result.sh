#!/bin/bash
echo "=== Exporting wildfire_burn_severity_nbr result ==="

# Take final screenshot before checking files
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run a Python script to parse the output files and extract verification metadata
python3 << 'PYEOF'
import os
import json
import xml.etree.ElementTree as ET

result = {
    'task_start': 0,
    'dim_found': False,
    'dim_created_after_start': False,
    'nbr_band_found': False,
    'nbr_valid_pixel_expr': '',
    'burn_severity_found': False,
    'burn_severity_expr': '',
    'envi_found': False,
    'envi_created_after_start': False,
    'envi_is_valid': False
}

# 1. Read task start time
ts_file = '/tmp/task_start_ts.txt'
if os.path.exists(ts_file):
    with open(ts_file, 'r') as f:
        result['task_start'] = int(f.read().strip())

# 2. Check for BEAM-DIMAP product
dim_file = '/home/ga/snap_exports/burn_analysis.dim'
if not os.path.exists(dim_file):
    # Try searching broadly in case they saved it elsewhere
    for root, dirs, files in os.walk('/home/ga'):
        if 'snap_data' in root:
            continue
        for f in files:
            if f.endswith('.dim') and 'burn' in f.lower():
                dim_file = os.path.join(root, f)
                break

if os.path.exists(dim_file):
    result['dim_found'] = True
    mtime = int(os.path.getmtime(dim_file))
    if mtime > result['task_start']:
        result['dim_created_after_start'] = True
    
    try:
        tree = ET.parse(dim_file)
        root = tree.getroot()
        for sbi in root.iter('Spectral_Band_Info'):
            name_el = sbi.find('BAND_NAME')
            if name_el is not None and name_el.text:
                bname = name_el.text.strip()
                bname_lower = bname.lower()
                
                # Check NBR Band
                if 'nbr' in bname_lower:
                    result['nbr_band_found'] = True
                    valid_expr_el = sbi.find('VALID_PIXEL_EXPRESSION')
                    if valid_expr_el is not None and valid_expr_el.text:
                        result['nbr_valid_pixel_expr'] = valid_expr_el.text.strip()
                
                # Check Burn Severity Band
                if 'severity' in bname_lower or 'burn' in bname_lower and bname_lower != 'nbr':
                    result['burn_severity_found'] = True
                    virtual_expr_el = sbi.find('VIRTUAL_BAND_EXPRESSION')
                    if virtual_expr_el is not None and virtual_expr_el.text:
                        result['burn_severity_expr'] = virtual_expr_el.text.strip()
    except Exception as e:
        print(f"Error parsing XML: {e}")

# 3. Check for ENVI product
envi_hdr = '/home/ga/snap_exports/burn_analysis.hdr'
if not os.path.exists(envi_hdr):
    # Search for any .hdr files recently created
    for root, dirs, files in os.walk('/home/ga'):
        if 'snap_data' in root:
            continue
        for f in files:
            if f.endswith('.hdr') and 'burn' in f.lower():
                envi_hdr = os.path.join(root, f)
                break

if os.path.exists(envi_hdr):
    result['envi_found'] = True
    mtime = int(os.path.getmtime(envi_hdr))
    if mtime > result['task_start']:
        result['envi_created_after_start'] = True
    
    # Read first few lines to check if it's a valid ENVI header
    try:
        with open(envi_hdr, 'r') as f:
            content = f.read(1024)
            if 'ENVI' in content:
                result['envi_is_valid'] = True
    except:
        pass

# Save results to a temporary JSON for verifier extraction
with open('/tmp/burn_severity_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export results computed and saved to /tmp/burn_severity_result.json")
PYEOF

echo "=== Export Complete ==="