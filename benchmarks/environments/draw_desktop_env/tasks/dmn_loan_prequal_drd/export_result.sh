#!/bin/bash
# Do NOT use set -e

echo "=== Exporting dmn_loan_prequal_drd result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/dmn_task_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/loan_drd.drawio"
PNG_FILE="/home/ga/Desktop/loan_drd.png"

FILE_EXISTS="false"
PNG_EXISTS="false"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
FILE_MODIFIED_AFTER_START="false"

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# Analyze the draw.io file content using Python
python3 << 'PYEOF' > /tmp/dmn_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/loan_drd.drawio"
result = {
    "num_shapes": 0,
    "num_edges": 0,
    "inputs_found": [],
    "decisions_found": [],
    "connections": [],
    "shape_types": {"ellipse": 0, "rectangle": 0, "dmn_input": 0, "dmn_decision": 0},
    "error": None
}

REQUIRED_INPUTS = ["credit score", "annual income", "loan amount", "monthly debt"]
REQUIRED_DECISIONS = ["risk tier", "dti ratio", "pre-qualification result", "pre-qual", "result"]

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

        all_cells = []
        # Handle compressed diagram data if present
        diagrams = root.findall('diagram')
        if diagrams:
            for diag in diagrams:
                inner_root = decompress_diagram(diag.text or '')
                if inner_root is not None:
                    all_cells.extend(list(inner_root.iter('mxCell')))
        
        # Also check uncompressed
        for cell in root.iter('mxCell'):
            if cell not in all_cells:
                all_cells.append(cell)

        # Analyze cells
        # We need to map IDs to Values to reconstruct topology
        id_to_value = {}
        edges = []

        for cell in all_cells:
            cid = cell.get('id')
            val = (cell.get('value') or '').strip().lower()
            style = (cell.get('style') or '').lower()
            vertex = cell.get('vertex') == '1'
            edge = cell.get('edge') == '1'

            # Clean HTML from value
            clean_val = re.sub(r'<[^>]+>', ' ', val)
            clean_val = re.sub(r'\s+', ' ', clean_val).strip()

            if vertex:
                result["num_shapes"] += 1
                if clean_val:
                    id_to_value[cid] = clean_val
                    
                    # Categorize based on text content
                    # Check for inputs
                    for req in REQUIRED_INPUTS:
                        if req in clean_val:
                            result["inputs_found"].append(req)
                            break
                    # Check for decisions
                    for req in REQUIRED_DECISIONS:
                        if req in clean_val:
                            result["decisions_found"].append(req)
                            break
                
                # Check shape style
                if "ellipse" in style or "shape=dmn.input" in style:
                    result["shape_types"]["ellipse"] += 1
                if "rectangle" in style or "shape=dmn.decision" in style:
                    result["shape_types"]["rectangle"] += 1

            elif edge:
                result["num_edges"] += 1
                source = cell.get('source')
                target = cell.get('target')
                if source and target:
                    edges.append((source, target))

        # Reconstruct connection topology textually
        # List of "Source Value -> Target Value"
        for s, t in edges:
            s_val = id_to_value.get(s, "Unknown")
            t_val = id_to_value.get(t, "Unknown")
            result["connections"].append(f"{s_val} -> {t_val}")

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
    "png_exists": $PNG_EXISTS,
    "analysis": $(cat /tmp/dmn_analysis.json)
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="