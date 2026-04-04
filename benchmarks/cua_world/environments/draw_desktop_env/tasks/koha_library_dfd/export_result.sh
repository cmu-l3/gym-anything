#!/bin/bash
echo "=== Exporting koha_library_dfd result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Desktop/koha_library_dfd.drawio"
PNG_FILE="/home/ga/Desktop/koha_library_dfd.png"

# Capture final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check files
FILE_EXISTS="false"
PNG_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0
PNG_SIZE=0

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

# Python script to parse draw.io XML (handles compression) and extract semantic data
python3 << 'PYEOF' > /tmp/drawio_analysis.json
import json
import os
import re
import base64
import zlib
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/koha_library_dfd.drawio"
result = {
    "pages": [],
    "total_shapes": 0,
    "total_edges": 0,
    "entities_found": [],
    "processes_found": [],
    "stores_found": [],
    "dfd_labels_found": False
}

def decode_diagram(text):
    if not text: return None
    try:
        # Try standard draw.io compression (base64 + deflate -15)
        return zlib.decompress(base64.b64decode(text), -15)
    except:
        try:
            # Try URL decoding
            decoded = unquote(text)
            if decoded.startswith('<'): return decoded.encode('utf-8')
        except:
            pass
    return None

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        diagrams = root.findall('diagram')
        
        for d in diagrams:
            page_name = d.get('name', 'Page')
            page_data = {
                "name": page_name,
                "shapes": 0,
                "edges": 0,
                "text_content": []
            }
            
            # Get content (inline or text node)
            content = None
            mx_graph = d.find('mxGraphModel')
            if mx_graph is not None:
                # Uncompressed XML inside
                root_cell = mx_graph.find('root')
                cells = root_cell.findall('mxCell') if root_cell else []
            else:
                # Compressed text node
                raw_xml = decode_diagram(d.text)
                if raw_xml:
                    mx_root = ET.fromstring(raw_xml)
                    root_cell = mx_root.find('root')
                    cells = root_cell.findall('mxCell') if root_cell else []
                else:
                    cells = []

            for cell in cells:
                val = cell.get('value', '')
                style = cell.get('style', '')
                
                # Check for DFD notation (P1, D1, etc)
                if re.search(r'\b[PD][1-7]\b', val):
                    result["dfd_labels_found"] = True

                if cell.get('vertex') == '1':
                    page_data["shapes"] += 1
                    result["total_shapes"] += 1
                    if val: page_data["text_content"].append(val)
                elif cell.get('edge') == '1':
                    page_data["edges"] += 1
                    result["total_edges"] += 1
                    if val: page_data["text_content"].append(val)
            
            result["pages"].append(page_data)

        # Aggregate text analysis
        all_text = " ".join([t for p in result["pages"] for t in p["text_content"]]).lower()
        
        # Check Entities
        entities = ["patron", "librarian", "publisher", "vendor", "oclc", "worldcat", "sip2", "kiosk"]
        for e in entities:
            if e in all_text:
                result["entities_found"].append(e)
                
        # Check Processes
        processes = ["circulation", "cataloging", "acquisitions", "opac", "patron management", "serials", "reports"]
        for p in processes:
            if p in all_text:
                result["processes_found"].append(p)
                
        # Check Stores
        stores = ["biblio", "catalog", "patron database", "transaction", "ledger", "registry"]
        for s in stores:
            if s in all_text:
                result["stores_found"].append(s)

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Merge analysis into final JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/drawio_analysis.json)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"