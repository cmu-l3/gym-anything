#!/bin/bash
echo "=== Exporting Traffic Congestion CLD Result ==="

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python Script to Analyze the .drawio file
# This runs INSIDE the container to extract verification data
cat << 'PY_SCRIPT' > /tmp/analyze_drawio.py
import sys
import os
import zlib
import base64
import urllib.parse
import json
import re
import xml.etree.ElementTree as ET

def decode_drawio_content(encoded_text):
    """Decode draw.io compressed diagram content."""
    try:
        url_decoded = urllib.parse.unquote(encoded_text.strip())
        data = base64.b64decode(url_decoded + '==')
        xml_str = zlib.decompress(data, -15).decode('utf-8')
        return xml_str
    except Exception as e:
        return None

def analyze_file(filepath):
    if not os.path.exists(filepath):
        return {"exists": False}
    
    # Get file stats
    stats = os.stat(filepath)
    result = {
        "exists": True,
        "size": stats.st_size,
        "mtime": stats.st_mtime,
        "nodes": [],
        "edges": [],
        "labels": [],
        "polarities_found": 0,
        "loops_found": [],
        "legend_found": False
    }

    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
    except Exception as e:
        result["error"] = str(e)
        return result

    # Flatten XML to find all mxCell elements
    all_cells = []
    
    if root.tag == 'mxfile':
        for diag in root.findall('diagram'):
            # Check if content is compressed
            if diag.text and diag.text.strip():
                xml_content = decode_drawio_content(diag.text)
                if xml_content:
                    try:
                        diag_tree = ET.fromstring(xml_content)
                        all_cells.extend(diag_tree.findall('.//mxCell'))
                    except:
                        pass
            # Also check for uncompressed children (like the starter file)
            all_cells.extend(diag.findall('.//mxCell'))
    else:
        # Just a raw mxGraphModel
        all_cells.extend(root.findall('.//mxCell'))

    # Analyze cells
    for cell in all_cells:
        value = cell.get('value', '').strip()
        style = cell.get('style', '')
        vertex = cell.get('vertex')
        edge = cell.get('edge')
        
        # Strip HTML tags from value for text analysis
        text = re.sub('<[^<]+?>', '', value)
        
        if vertex == '1':
            result['nodes'].append(text)
            result['labels'].append(text)
            
            # Check for legend (usually a container or specific text)
            if "Legend" in text or "Notation" in text:
                result['legend_found'] = True
            
            # Check for loop annotations (R1, B1, etc.)
            if re.search(r'\b[RB][1-4]\b', text):
                result['loops_found'].append(text)

        if edge == '1':
            result['edges'].append(text)
            # Check for polarity in edge labels
            if '+' in text or '-' in text or 'plus' in text.lower() or 'minus' in text.lower():
                result['polarities_found'] += 1
            # Sometimes polarity is a separate text label floating near the edge
            # This is hard to link without coordinate math, so we rely on counting '+' labels in nodes too
        
        # Checking floating text labels (which are vertices in draw.io) for polarity
        if vertex == '1' and (text.strip() == '+' or text.strip() == '-' or text.strip() == '(+)' or text.strip() == '(-)'):
            result['polarities_found'] += 1

    return result

# Run analysis
data = analyze_file('/home/ga/Diagrams/traffic_congestion_cld.drawio')

# Check PDF
pdf_path = '/home/ga/Diagrams/traffic_congestion_cld.pdf'
data['pdf_exists'] = os.path.exists(pdf_path)
if data['pdf_exists']:
    data['pdf_size'] = os.path.getsize(pdf_path)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
PY_SCRIPT

# 3. Execute Analysis
python3 /tmp/analyze_drawio.py

# 4. Check for application running
if pgrep -f "draw.io" > /dev/null; then
    APP_RUNNING=true
else
    APP_RUNNING=false
fi

# 5. Add execution metadata to result
# Use jq if available, otherwise simple python append
python3 -c "
import json
with open('/tmp/task_result.json', 'r') as f:
    d = json.load(f)
d['app_running'] = $APP_RUNNING
with open('/tmp/task_start_time.txt', 'r') as f:
    d['start_time'] = int(f.read().strip())
with open('/tmp/task_result.json', 'w') as f:
    json.dump(d, f)
"

cat /tmp/task_result.json
echo "=== Export Complete ==="