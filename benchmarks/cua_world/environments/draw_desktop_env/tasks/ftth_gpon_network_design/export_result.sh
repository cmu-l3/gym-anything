#!/bin/bash
# Do NOT use set -e

echo "=== Exporting FTTH GPON Design Result ==="

DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/ftth_design.drawio"
PDF_FILE="/home/ga/Desktop/ftth_design.pdf"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
PDF_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

# Check .drawio file
if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check .pdf file
if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
fi

# Python script to analyze the draw.io XML content
# It handles decompression (draw.io standard) and extracts text for calculation verification
python3 << 'PYEOF' > /tmp/gpon_analysis.json 2>/dev/null || true
import json
import re
import os
import base64
import zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/ftth_design.drawio"
result = {
    "text_content": [],
    "shape_count": 0,
    "has_olt": False,
    "has_splitter": False,
    "has_ont": False,
    "house_a_val": None,
    "house_b_val": None,
    "house_c_val": None,
    "error": None
}

def decompress_diagram(content):
    if not content or not content.strip():
        return None
    try:
        # Try standard raw deflate (no header)
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except Exception:
        pass
    try:
        # Try URL decoding (sometimes used)
        from urllib.parse import unquote
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'):
            return ET.fromstring(decoded_str)
    except Exception:
        pass
    return None

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Extract all cells
        cells = []
        diagrams = root.findall('diagram')
        for d in diagrams:
            if d.text:
                inner = decompress_diagram(d.text)
                if inner:
                    cells.extend(list(inner.iter('mxCell')))
            else:
                # Uncompressed format
                cells.extend(list(d.iter('mxCell')))
        
        # Fallback for uncompressed root
        for cell in root.iter('mxCell'):
            if cell not in cells:
                cells.append(cell)

        all_text = []
        for cell in cells:
            val = cell.get('value', '')
            if not val:
                continue
            
            # Simple HTML stripping
            clean_val = re.sub(r'<[^>]+>', ' ', val).strip()
            if clean_val:
                all_text.append(clean_val)
                
            # Check keywords
            lower_val = clean_val.lower()
            if 'olt' in lower_val: result['has_olt'] = True
            if 'split' in lower_val: result['has_splitter'] = True
            if 'ont' in lower_val or 'house' in lower_val: result['has_ont'] = True
            
            if cell.get('vertex') == '1':
                result['shape_count'] += 1

        result['text_content'] = all_text

        # Heuristic extraction of dBm values near House labels
        # We look for numbers roughly in the range of -15 to -25 in the text
        # This is a bit fuzzy because association between label and shape is loose in XML
        
        # Regex to find dBm-like strings: "-19.67", "-20.5 dBm", etc.
        dbm_pattern = re.compile(r'-\d+\.?\d*')
        
        # Just collect all numbers found in the diagram text
        numbers_found = []
        for t in all_text:
            matches = dbm_pattern.findall(t)
            for m in matches:
                try:
                    numbers_found.append(float(m))
                except:
                    pass
        
        result['numbers_found'] = numbers_found

    except Exception as e:
        result['error'] = str(e)

print(json.dumps(result))
PYEOF

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "pdf_exists": $PDF_EXISTS,
    "analysis": $(cat /tmp/gpon_analysis.json 2>/dev/null || echo "{}"),
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="