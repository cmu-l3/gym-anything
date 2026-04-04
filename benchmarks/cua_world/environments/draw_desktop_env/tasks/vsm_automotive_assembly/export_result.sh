#!/bin/bash
# export_result.sh for vsm_automotive_assembly

echo "=== Exporting Task Results ==="

# 1. Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Variables
DRAWIO_FILE="/home/ga/Desktop/acme_vsm.drawio"
PNG_FILE="/home/ga/Desktop/acme_vsm.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# 3. Check File Existence & Timestamps
FILE_EXISTS=false
FILE_MODIFIED_DURING_TASK=false
PNG_EXISTS=false
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c %s "$DRAWIO_FILE")
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK=true
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS=true
fi

# 4. Parse draw.io XML content (Python)
# draw.io files are often compressed XML. We need to handle both plain and compressed.
python3 << 'PYEOF' > /tmp/vsm_analysis.json 2>/dev/null
import sys
import zlib
import base64
import xml.etree.ElementTree as ET
from urllib.parse import unquote
import json
import os
import re

filepath = "/home/ga/Desktop/acme_vsm.drawio"
result = {
    "text_content": [],
    "shapes_count": 0,
    "edges_count": 0,
    "page_count": 0,
    "has_triangles": False,
    "has_ladder": False,
    "found_metrics": {
        "cycle_times": 0,
        "inventories": 0,
        "lead_time_calc": False,
        "processing_time_calc": False
    },
    "entities": {
        "supplier": False,
        "customer": False,
        "processes": 0
    }
}

def decode_drawio(content):
    """Decompresses draw.io content if needed."""
    try:
        # Check if URL encoded
        if '%' in content:
            content = unquote(content)
        
        # Check if base64/deflate
        # draw.io compressed XML usually starts with <mxfile>...<diagram>... BASE64 ...</diagram>
        try:
            tree = ET.fromstring(content)
            diagram = tree.find('diagram')
            if diagram is not None and diagram.text:
                data = base64.b64decode(diagram.text)
                xml_str = zlib.decompress(data, -15).decode('utf-8')
                return ET.fromstring(unquote(xml_str)) # Sometimes double encoded
        except:
            pass
            
        # Maybe it's already plain XML
        return ET.fromstring(content)
    except Exception as e:
        return None

if os.path.exists(filepath):
    try:
        with open(filepath, 'r') as f:
            raw_content = f.read()
        
        root = decode_drawio(raw_content)
        
        if root is not None:
            # Flatten all text
            all_text = ""
            
            # Count elements
            for elem in root.iter('mxCell'):
                val = elem.get('value', '')
                style = elem.get('style', '')
                
                # Check metrics in value
                if val:
                    clean_val = re.sub(r'<[^>]+>', ' ', val).strip() # Strip HTML
                    if clean_val:
                        all_text += " " + clean_val.lower()
                        result["text_content"].append(clean_val)
                
                # Shapes
                if elem.get('vertex') == '1':
                    result["shapes_count"] += 1
                    # Detect triangles (Inventory)
                    if 'triangle' in style or 'iso' in style: # 'iso' for some VSM shapes
                        result["has_triangles"] = True
                    # Detect timeline ladder symbols
                    if 'timeline' in style or 'ladder' in style:
                        result["has_ladder"] = True

                # Edges
                if elem.get('edge') == '1':
                    result["edges_count"] += 1

            # Analysis of text content
            
            # 1. Process Names
            procs = ["stamping", "welding", "assembly"]
            found_procs = sum(1 for p in procs if p in all_text)
            result["entities"]["processes"] = found_procs

            # 2. External Entities
            if "michigan" in all_text or "steel" in all_text:
                result["entities"]["supplier"] = True
            if "state street" in all_text or "customer" in all_text:
                result["entities"]["customer"] = True

            # 3. Metrics
            # Cycle times: 1, 38, 46, 62, 40
            cts = ["1s", "1 s", "38", "46", "62", "40"]
            result["found_metrics"]["cycle_times"] = sum(1 for c in cts if c in all_text)
            
            # Inventories: 4600, 1100, 1600, 1200, 2700
            invs = ["4600", "1100", "1600", "1200", "2700"]
            result["found_metrics"]["inventories"] = sum(1 for i in invs if i in all_text)

            # Calculations
            if "23.6" in all_text or "24 days" in all_text:
                result["found_metrics"]["lead_time_calc"] = True
            if "187" in all_text:
                result["found_metrics"]["processing_time_calc"] = True

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 5. Merge Results
ANALYSIS=$(cat /tmp/vsm_analysis.json)

# Safely construct JSON
cat > "$RESULT_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "analysis": $ANALYSIS
}
EOF

# 6. Permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"