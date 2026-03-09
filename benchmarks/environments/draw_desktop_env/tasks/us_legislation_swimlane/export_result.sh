#!/bin/bash
# Export script for us_legislation_swimlane

echo "=== Exporting Task Results ==="

# 1. Basic File Checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Desktop/legislation_process.drawio"
PNG_FILE="/home/ga/Desktop/legislation_process.png"

FILE_EXISTS="false"
FILE_MODIFIED="false"
PNG_EXISTS="false"
PNG_SIZE=0
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DRAWIO_FILE")
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE")
fi

# 2. Python Script for Deep XML Analysis (Swimlanes, Keywords, Structure)
python3 << 'PYEOF' > /tmp/xml_analysis.json
import json
import base64
import zlib
import re
import os
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/legislation_process.drawio"
result = {
    "page_count": 0,
    "swimlane_count": 0,
    "process_steps": 0,
    "decisions": 0,
    "terminators": 0,
    "edges": 0,
    "keywords_found": [],
    "override_page_found": False,
    "swimlane_labels": []
}

def decode_diagram(text):
    if not text: return None
    try:
        # Try Base64 + Deflate (Standard draw.io)
        decoded = base64.b64decode(text)
        return zlib.decompress(decoded, -15)
    except:
        try:
            # Try URL Decode (Alternate format)
            return unquote(text)
        except:
            return None

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        diagrams = root.findall('diagram')
        result['page_count'] = len(diagrams)
        
        all_text_content = ""
        
        for diag in diagrams:
            # Check for page titles
            page_name = diag.get('name', '').lower()
            if 'override' in page_name or 'veto' in page_name:
                result['override_page_found'] = True

            # Get content
            raw_xml = decode_diagram(diag.text)
            if not raw_xml: continue
            
            # Parse inner XML
            try:
                page_root = ET.fromstring(raw_xml)
            except:
                continue
                
            for cell in page_root.iter('mxCell'):
                style = (cell.get('style') or "").lower()
                value = (cell.get('value') or "").lower()
                is_vertex = cell.get('vertex') == '1'
                is_edge = cell.get('edge') == '1'
                
                # Strip HTML from value for keyword search
                clean_value = re.sub('<[^<]+?>', ' ', value)
                all_text_content += " " + clean_value
                
                if is_vertex:
                    # Detect Swimlanes
                    if 'swimlane' in style:
                        result['swimlane_count'] += 1
                        result['swimlane_labels'].append(clean_value.strip())
                    
                    # Detect Decisions
                    elif 'rhombus' in style or 'decision' in style:
                        result['decisions'] += 1
                        
                    # Detect Terminators
                    elif 'ellipse' in style or 'terminator' in style or 'start' in style or 'end' in style:
                        result['terminators'] += 1
                        
                    # Detect Process Steps (exclude swimlanes/decisions/terminators)
                    elif 'rounded' in style or 'rectangle' in style or 'process' in style:
                         # Filter out empty or structural shapes
                         if len(clean_value.strip()) > 2: 
                            result['process_steps'] += 1
                            
                if is_edge:
                    result['edges'] += 1

        # Keyword Analysis
        keywords = ["house", "senate", "president", "conference", "committee", "vote", "veto", "bill", "law", "override", "sign"]
        found = []
        for kw in keywords:
            if kw in all_text_content:
                found.append(kw)
        result['keywords_found'] = found
        
    except Exception as e:
        result['error'] = str(e)

print(json.dumps(result))
PYEOF

# 3. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Construct Result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/xml_analysis.json)
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json