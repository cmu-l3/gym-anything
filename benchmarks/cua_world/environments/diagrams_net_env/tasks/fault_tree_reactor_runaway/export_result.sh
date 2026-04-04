#!/bin/bash
echo "=== Exporting Fault Tree Results ==="

# Define paths
DIAGRAM_PATH="/home/ga/Diagrams/reactor_fta.drawio"
PDF_PATH="/home/ga/Diagrams/reactor_fta.pdf"
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python Script to Parse XML and Analyze Content
# We use Python here because grep is too brittle for XML structure and content extraction
python3 -c "
import sys
import os
import re
import json
import zlib
import base64
from urllib.parse import unquote

def decode_mxfile(fpath):
    try:
        with open(fpath, 'r') as f:
            content = f.read()
        
        # Check if it's a standard XML file first
        if '<mxGraphModel' in content:
            return content
            
        # If it's a compressed mxfile
        if '<diagram' in content:
            # Extract the text content of the diagram tag
            match = re.search(r'<diagram[^>]*>(.*?)</diagram>', content, re.DOTALL)
            if match:
                raw_data = match.group(1)
                try:
                    # draw.io compression: base64 -> deflate
                    decoded_data = base64.b64decode(raw_data)
                    xml_data = zlib.decompress(decoded_data, -15).decode('utf-8')
                    return unquote(xml_data)
                except Exception as e:
                    return f'Error decoding: {str(e)}'
        return content
    except Exception as e:
        return ''

diagram_xml = decode_mxfile('$DIAGRAM_PATH')
file_exists = os.path.exists('$DIAGRAM_PATH')
pdf_exists = os.path.exists('$PDF_PATH')

# Metrics
shape_count = diagram_xml.count('vertex=\"1\"')
edge_count = diagram_xml.count('edge=\"1\"')

# Text Content Analysis (case insensitive)
content_lower = diagram_xml.lower()

# Required terms checking
terms_to_check = [
    'coolant', 'pump', 'valve', 'power', 'calibration', 
    'thermocouple', 'sis', 'sensor', 'esd', 'operator'
]
found_terms = [t for t in terms_to_check if t in content_lower]

# Probability Pattern Checking (e.g., '1.0e-3', '10^-3')
# Looking for scientific notation or exponent patterns often used in FTA
prob_pattern_count = len(re.findall(r'[0-9][\.,][0-9].*e-[0-9]', content_lower)) + \
                     len(re.findall(r'10\^-?[0-9]', content_lower))

# Color Code Checking
# Blue, Orange, Red hex codes
colors_found = []
if '#dae8fc' in content_lower: colors_found.append('blue')
if '#ffe6cc' in content_lower: colors_found.append('orange')
if '#f8cecc' in content_lower: colors_found.append('red')

result = {
    'file_exists': file_exists,
    'pdf_exists': pdf_exists,
    'shape_count': shape_count,
    'edge_count': edge_count,
    'found_terms': found_terms,
    'prob_pattern_count': prob_pattern_count,
    'colors_found': colors_found,
    'file_size': os.path.getsize('$DIAGRAM_PATH') if file_exists else 0,
    'timestamp_valid': os.path.getmtime('$DIAGRAM_PATH') > $TASK_START_TIME if file_exists else False
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 3. Final cleanup and permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json