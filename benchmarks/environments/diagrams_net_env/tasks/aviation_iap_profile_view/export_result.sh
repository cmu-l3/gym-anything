#!/bin/bash
echo "=== Exporting Aviation IAP Task Results ==="

# Files
DRAWIO_FILE="/home/ga/Diagrams/ksfo_ils_28r_profile.drawio"
PDF_FILE="/home/ga/Diagrams/ksfo_ils_28r_profile.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_JSON="/tmp/task_result.json"

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamps
DRAWIO_EXISTS=false
PDF_EXISTS=false
FILE_MODIFIED=false

if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS=true
    MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED=true
    fi
fi

if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS=true
    # Verify PDF has non-zero size
    if [ $(stat -c %s "$PDF_FILE") -lt 100 ]; then
        PDF_EXISTS=false
    fi
fi

# 3. Parse DrawIO Content (Python embedded)
# We need to check vertical topology: ARCHI(y) < DUMBA(y) < RWY(y)
# Note: In screen coords, lower Y value is higher on screen.

python3 -c "
import sys
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import json
import re

def decode_drawio(content):
    try:
        # Standard draw.io compression: URL encoded -> Base64 -> Deflate (no header)
        if '<mxfile' in content and 'compressed=\"false\"' in content:
            return content
        
        # Extract content inside <diagram> tags if present
        root = ET.fromstring(content)
        if root.tag == 'mxfile':
            diagram = root.find('diagram')
            if diagram is not None and diagram.text:
                data = base64.b64decode(diagram.text)
                try:
                    return zlib.decompress(data, -15).decode('utf-8')
                except:
                    return zlib.decompress(data).decode('utf-8')
        return content
    except Exception as e:
        return ''

result = {
    'archi_found': False,
    'dumba_found': False,
    'rwy_found': False,
    'alt_4000_found': False,
    'alt_1800_found': False,
    'freq_found': False,
    'archi_y': 10000,
    'dumba_y': 10000,
    'rwy_y': 0,
    'has_dashed_line': False,
    'text_content': []
}

try:
    with open('$DRAWIO_FILE', 'r') as f:
        raw_content = f.read()
    
    xml_content = decode_drawio(raw_content)
    
    # Simple parsing logic since full XML parsing of mxGraph is complex
    # We look for text labels and their geometry in the decoded XML
    
    # 1. Extract text
    # DrawIO labels are in value=\"...\" attributes.
    
    root = ET.fromstring(f'<root>{xml_content}</root>') # Wrap to ensure validity if partial
    
    for cell in root.iter('mxCell'):
        val = cell.get('value', '')
        style = cell.get('style', '')
        geo = cell.find('mxGeometry')
        
        if val:
            # Clean HTML tags from label
            text = re.sub('<[^<]+?>', '', val).strip()
            result['text_content'].append(text)
            
            upper_text = text.upper()
            
            # Check content
            if 'ARCHI' in upper_text:
                result['archi_found'] = True
                if geo is not None: result['archi_y'] = float(geo.get('y', 10000))
            
            if 'DUMBA' in upper_text:
                result['dumba_found'] = True
                if geo is not None: result['dumba_y'] = float(geo.get('y', 10000))
                
            if 'RWY' in upper_text or '28R' in upper_text:
                # We need to distinguish RWY label from others if possible, 
                # but for this specific chart, RWY is the lowest point usually.
                # Let's track specifically 'RWY' or '28R' near bottom
                result['rwy_found'] = True
                if geo is not None: result['rwy_y'] = float(geo.get('y', 0))
            
            if '4000' in text: result['alt_4000_found'] = True
            if '1800' in text: result['alt_1800_found'] = True
            if '111.7' in text: result['freq_found'] = True

        # Check for dashed lines (Missed Approach)
        # Style usually contains 'dashed=1' or 'dashPattern'
        if 'dashed=1' in style or 'dashPattern' in style:
            # And it should probably be an edge
            if cell.get('edge') == '1':
                result['has_dashed_line'] = True

except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
" > /tmp/content_analysis.json

# 4. Merge results
cat <<EOF > "$OUTPUT_JSON"
{
    "drawio_exists": $DRAWIO_EXISTS,
    "pdf_exists": $PDF_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "content_analysis": $(cat /tmp/content_analysis.json)
}
EOF

echo "Export complete. Result saved to $OUTPUT_JSON"