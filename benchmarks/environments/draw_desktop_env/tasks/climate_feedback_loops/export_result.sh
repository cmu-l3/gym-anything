#!/bin/bash
# Do NOT use set -e

echo "=== Exporting climate_feedback_loops result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/loops_task_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/climate_loops.drawio"
PNG_FILE="/home/ga/Desktop/climate_loops.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check Drawio File
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"
if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check PNG File
PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# Parse the drawio file to extract graph structure
# We use Python here to handle the XML/compression and export a simplified JSON graph representation
# that verifier.py can easily check.
python3 << 'PYEOF' > /tmp/graph_structure.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/climate_loops.drawio"
result = {
    "nodes": [],
    "edges": [],
    "labels": [],
    "text_content": "",
    "error": None
}

def decompress_diagram(content):
    if not content or not content.strip(): return None
    try:
        # standard deflate
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except: pass
    try:
        # url encoded
        from urllib.parse import unquote
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'): return ET.fromstring(decoded_str)
    except: pass
    return None

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Find cells (handling compression)
        all_cells = []
        # Check diagrams
        for diag in root.findall('.//diagram'):
            if diag.text:
                xml_root = decompress_diagram(diag.text)
                if xml_root: all_cells.extend(list(xml_root.iter('mxCell')))
        # Check direct root
        all_cells.extend(list(root.iter('mxCell')))
        
        # Map IDs to values for easy graph building
        id_map = {}
        
        # Pass 1: Nodes
        for cell in all_cells:
            cid = cell.get('id')
            val = (cell.get('value') or '').strip()
            # Clean HTML from value
            clean_val = re.sub(r'<[^>]+>', ' ', val).strip()
            
            # Identify if it's an edge or vertex
            is_edge = cell.get('edge') == '1'
            is_vertex = cell.get('vertex') == '1'
            
            if is_vertex:
                result["nodes"].append({"id": cid, "text": clean_val})
                result["text_content"] += " " + clean_val
                id_map[cid] = clean_val
            
            # Collect text labels that might be floating (polarity)
            if clean_val and not is_edge: # floating text often vertex=1 too
                result["labels"].append(clean_val)

        # Pass 2: Edges
        for cell in all_cells:
            if cell.get('edge') == '1':
                source = cell.get('source')
                target = cell.get('target')
                val = (cell.get('value') or '').strip()
                clean_val = re.sub(r'<[^>]+>', ' ', val).strip()
                
                if source and target:
                    result["edges"].append({
                        "source": source,
                        "target": target,
                        "label": clean_val
                    })
                    if clean_val:
                        result["labels"].append(clean_val)
                        result["text_content"] += " " + clean_val

    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

print(json.dumps(result))
PYEOF

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "task_start": $TASK_START
}
EOF

# Move result
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="