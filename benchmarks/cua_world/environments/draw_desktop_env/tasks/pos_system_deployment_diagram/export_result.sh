#!/bin/bash
# Do NOT use set -e

echo "=== Exporting pos_system_deployment_diagram result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/pos_task_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/pos_deployment.drawio"
PNG_FILE="/home/ga/Desktop/pos_deployment.png"

# Basic file checks
FILE_EXISTS="false"
FILE_SIZE=0
PNG_EXISTS="false"
PNG_SIZE=0
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
FILE_MODIFIED_AFTER_START="false"

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
    echo "Found drawio file: $DRAWIO_FILE ($FILE_SIZE bytes)"
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
    echo "Found PNG file: $PNG_FILE ($PNG_SIZE bytes)"
fi

# Analyze diagram content using Python
# We need to parse XML to check for:
# 1. Hardware Nodes (cubes)
# 2. Software Artifacts (and their parent containment)
# 3. Connection labels
python3 << 'PYEOF' > /tmp/pos_diagram_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/pos_deployment.drawio"
result = {
    "nodes_found": [],
    "artifacts_found": [],
    "edges_found": [],
    "nesting_map": {}, # child_text -> parent_text
    "all_text": "",
    "error": None
}

def decompress_diagram(content):
    if not content or not content.strip():
        return None
    try:
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except Exception:
        pass
    try:
        from urllib.parse import unquote
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'):
            return ET.fromstring(decoded_str)
    except Exception:
        pass
    return None

try:
    if not os.path.exists(filepath):
        result["error"] = "File not found"
    else:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Get all cells (handling compression if needed)
        all_cells = []
        pages = root.findall('.//diagram')
        if pages:
            for page in pages:
                # Try inline
                cells = list(page.iter('mxCell'))
                if cells:
                    all_cells.extend(cells)
                else:
                    # Try compressed
                    inner_root = decompress_diagram(page.text or '')
                    if inner_root is not None:
                        all_cells.extend(list(inner_root.iter('mxCell')))
        else:
            # Try root directly
            all_cells = list(root.iter('mxCell'))

        # Build ID map for nesting analysis
        id_to_text = {}
        cells_by_id = {}

        # First pass: collect text and IDs
        for cell in all_cells:
            cid = cell.get('id')
            val = (cell.get('value') or '').strip()
            style = (cell.get('style') or '').lower()
            
            # Clean HTML from value
            clean_val = re.sub(r'<[^>]+>', ' ', val).strip()
            
            if cid:
                cells_by_id[cid] = cell
                if clean_val:
                    id_to_text[cid] = clean_val
            
            if cell.get('vertex') == '1':
                # Check if it looks like a Node/Cube (3D) or Artifact
                if 'cube' in style or 'node' in style or 'uml' in style:
                    # Heuristic: Nodes often don't have parent other than default layer (usually '1')
                    # But we'll rely more on text content for classification in verifier
                    result["nodes_found"].append(clean_val)
                else:
                    result["artifacts_found"].append(clean_val) # Generic bucket for vertices
                    
            elif cell.get('edge') == '1':
                result["edges_found"].append(clean_val)

            result["all_text"] += " " + clean_val

        # Second pass: check nesting (parent-child relationships)
        for cell in all_cells:
            cid = cell.get('id')
            pid = cell.get('parent')
            
            if pid and pid in id_to_text and cid in id_to_text:
                child_text = id_to_text[cid]
                parent_text = id_to_text[pid]
                # Store nesting relationship
                result["nesting_map"][child_text] = parent_text

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/pos_diagram_analysis.json 2>/dev/null || echo "{}")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"