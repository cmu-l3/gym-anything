#!/bin/bash
echo "=== Exporting raster_to_tabular_csv_export result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract verification data via Python script
# We parse the XML and read the CSV header/lines to evaluate success
python3 << 'EOF'
import os
import json
import xml.etree.ElementTree as ET

task_start = 0
if os.path.exists('/tmp/task_start_time'):
    with open('/tmp/task_start_time', 'r') as f:
        task_start = int(f.read().strip())

dim_file = '/home/ga/snap_exports/ml_subset.dim'
csv_file = '/home/ga/snap_exports/ml_dataset.csv'

result = {
    'task_start': task_start,
    'dim_exists': False,
    'dim_recent': False,
    'dim_width': 0,
    'dim_height': 0,
    'csv_exists': False,
    'csv_recent': False,
    'csv_rows': 0,
    'csv_headers': []
}

# Analyze DIMAP header file for precise spatial subset verification
if os.path.exists(dim_file):
    result['dim_exists'] = True
    mtime = int(os.path.getmtime(dim_file))
    if mtime >= task_start:
        result['dim_recent'] = True
        
    try:
        tree = ET.parse(dim_file)
        root = tree.getroot()
        w_elem = root.find('.//Raster_Dimensions/WIDTH')
        h_elem = root.find('.//Raster_Dimensions/HEIGHT')
        if w_elem is not None:
            result['dim_width'] = int(w_elem.text)
        if h_elem is not None:
            result['dim_height'] = int(h_elem.text)
    except Exception as e:
        print(f"Error parsing DIMAP: {e}")

# Analyze CSV tabular output
if os.path.exists(csv_file):
    result['csv_exists'] = True
    mtime = int(os.path.getmtime(csv_file))
    if mtime >= task_start:
        result['csv_recent'] = True
        
    try:
        # Stream file to count lines rather than loading a potentially
        # massive failed-subset (e.g. 10+ million rows) into memory.
        line_count = 0
        headers = []
        with open(csv_file, 'r', encoding='utf-8', errors='ignore') as f:
            for i, line in enumerate(f):
                if i == 0:
                    header_line = line.strip()
                    # SNAP exports can use \t or , as separators based on locale/settings
                    sep = '\t' if '\t' in header_line else ','
                    headers = [x.strip().strip('"\'') for x in header_line.split(sep)]
                line_count += 1
                
                # Hard limit just to protect verification container memory
                if line_count > 1000000:
                    break
        
        result['csv_headers'] = headers
        result['csv_rows'] = max(0, line_count - 1) # exclude header
    except Exception as e:
        print(f"Error parsing CSV: {e}")
        
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

echo "Verification data exported to /tmp/task_result.json:"
cat /tmp/task_result.json

echo "=== Export complete ==="