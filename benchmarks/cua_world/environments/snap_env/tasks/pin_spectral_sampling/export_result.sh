#!/bin/bash
echo "=== Exporting pin_spectral_sampling result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Run a Python script to robustly extract all the verification data
python3 << 'PYEOF'
import os
import json
import re

task_start = 0
if os.path.exists('/tmp/task_start_time.txt'):
    try:
        task_start = int(open('/tmp/task_start_time.txt').read().strip())
    except:
        pass

dim_file = '/home/ga/snap_exports/landsat_with_pins.dim'
txt_file = '/home/ga/snap_exports/ground_truth_pins.txt'

result = {
    'task_start': task_start,
    'dim_exists': False,
    'dim_created_after_start': False,
    'txt_exists': False,
    'txt_size': 0,
    'txt_created_after_start': False,
    'pins_in_dim': [],
    'pins_in_txt': [],
    'txt_has_bands': False,
    'screenshot_exists': os.path.exists('/tmp/task_final_state.png')
}

# 1. Parse BEAM-DIMAP XML for Pins
if os.path.exists(dim_file):
    result['dim_exists'] = True
    if os.path.getmtime(dim_file) > task_start:
        result['dim_created_after_start'] = True
    
    try:
        with open(dim_file, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # Extract <Placemark> blocks using regex to bypass namespace strictness
        placemarks = re.findall(r'<Placemark>(.*?)</Placemark>', content, re.DOTALL)
        for pm in placemarks:
            name_match = re.search(r'<name>(.*?)</name>', pm)
            pixel_match = re.search(r'<pixelPos>(.*?)</pixelPos>', pm)
            
            if name_match:
                name = name_match.group(1).strip()
                px, py = None, None
                if pixel_match:
                    parts = pixel_match.group(1).strip().split()
                    if len(parts) >= 2:
                        try:
                            px, py = float(parts[0]), float(parts[1])
                        except ValueError:
                            pass
                result['pins_in_dim'].append({'name': name, 'x': px, 'y': py})
    except Exception as e:
        print(f"Error parsing DIM file: {e}")

# 2. Parse Exported Text File
if os.path.exists(txt_file):
    result['txt_exists'] = True
    result['txt_size'] = os.path.getsize(txt_file)
    if os.path.getmtime(txt_file) > task_start:
        result['txt_created_after_start'] = True
        
    try:
        with open(txt_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            for line in lines:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                
                # Split by tab or comma
                parts = [p.strip() for p in re.split(r'[\t,;]+', line) if p.strip()]
                
                # Identify if this row is a pin by checking for "Plot_"
                for i, p in enumerate(parts):
                    if p.startswith('Plot_'):
                        name = p
                        # Assume columns after name contain coordinates and bands
                        bands_data = parts[i+1:]
                        result['pins_in_txt'].append({
                            'name': name,
                            'columns_after_name': len(bands_data)
                        })
                        # Typically SNAP export has X, Y, Lon, Lat + Band values. 
                        # So if there are > 5 columns after the name, it contains band values.
                        if len(bands_data) >= 3:
                            result['txt_has_bands'] = True
                        break
    except Exception as e:
        print(f"Error parsing TXT file: {e}")

# Save result JSON safely
import tempfile
import shutil
temp_json = tempfile.NamedTemporaryFile(delete=False, mode='w', suffix='.json')
json.dump(result, temp_json, indent=2)
temp_json.close()

# Move to final location
os.system(f"cp {temp_json.name} /tmp/task_result.json")
os.system("chmod 666 /tmp/task_result.json")
os.unlink(temp_json.name)

print("Result JSON written to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="