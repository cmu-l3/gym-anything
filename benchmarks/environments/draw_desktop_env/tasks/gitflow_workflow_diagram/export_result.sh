#!/bin/bash
# Do NOT use set -e

echo "=== Exporting gitflow_workflow_diagram result ==="

# Capture final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/gitflow.drawio"
PNG_FILE="/home/ga/Desktop/gitflow.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check file existence and timestamps
FILE_EXISTS="false"
FILE_MODIFIED_AFTER_START="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
fi

PNG_EXISTS="false"
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# Deep XML analysis using Python
# This script parses the draw.io XML to find swimlanes and commits
python3 << 'PYEOF' > /tmp/gitflow_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/gitflow.drawio"
result = {
    "swimlane_structure_found": False,
    "lanes_found": [],
    "commit_nodes_count": 0,
    "edges_count": 0,
    "nodes_in_feature": 0,
    "nodes_in_develop": 0,
    "nodes_in_main": 0,
    "nodes_in_release": 0,
    "nodes_in_hotfix": 0,
    "tags_found": [],
    "error": None
}

REQUIRED_LANES = ["main", "hotfix", "release", "develop", "feature"]

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
        # Handle pages / compressed content
        pages = root.findall('.//diagram')
        for page in pages:
            inline_cells = list(page.iter('mxCell'))
            if inline_cells:
                all_cells.extend(inline_cells)
            else:
                inner_root = decompress_diagram(page.text or '')
                if inner_root is not None:
                    all_cells.extend(list(inner_root.iter('mxCell')))
        
        # Fallback to root cells
        if not all_cells:
            all_cells = list(root.iter('mxCell'))

        # Map cell IDs to their labels/styles for parent lookup
        cell_map = {}
        for cell in all_cells:
            cell_map[cell.get('id')] = cell

        # Analyze cells
        for cell in all_cells:
            val = (cell.get('value') or '').lower()
            style = (cell.get('style') or '').lower()
            cell_id = cell.get('id')
            parent_id = cell.get('parent')

            # 1. Identify Swimlanes
            if 'swimlane' in style or 'pool' in style:
                result["swimlane_structure_found"] = True
                # Clean label to extract lane name
                clean_val = re.sub(r'<[^>]+>', '', val).strip()
                if clean_val:
                    result["lanes_found"].append(clean_val)
            
            # 2. Identify Commits (usually circles/ellipses)
            # Commit nodes should be 'vertex="1"' and typically not swimlanes
            # We look for simple shapes that are likely commits
            is_commit = False
            if cell.get('vertex') == '1' and 'swimlane' not in style and cell_id not in ('0', '1'):
                # Check if it looks like a node (ellipse, circle, or just a box)
                if 'ellipse' in style or 'shape' in style or 'rounded' in style:
                    result["commit_nodes_count"] += 1
                    is_commit = True
                    
                    # Check for tags in text
                    if 'v1.0' in val:
                        result["tags_found"].append("v1.0")
                    if 'v1.0.1' in val:
                        result["tags_found"].append("v1.0.1")

            # 3. Check containment (which lane is this commit in?)
            if is_commit and parent_id and parent_id in cell_map:
                parent = cell_map[parent_id]
                parent_val = (parent.get('value') or '').lower()
                parent_val_clean = re.sub(r'<[^>]+>', '', parent_val).strip()
                
                if 'feature' in parent_val_clean:
                    result["nodes_in_feature"] += 1
                elif 'develop' in parent_val_clean:
                    result["nodes_in_develop"] += 1
                elif 'main' in parent_val_clean:
                    result["nodes_in_main"] += 1
                elif 'release' in parent_val_clean:
                    result["nodes_in_release"] += 1
                elif 'hotfix' in parent_val_clean:
                    result["nodes_in_hotfix"] += 1

            # 4. Count edges
            if cell.get('edge') == '1':
                result["edges_count"] += 1

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "analysis": $(cat /tmp/gitflow_analysis.json)
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"