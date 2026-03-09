#!/bin/bash
# Do NOT use set -e

echo "=== Exporting dc_metro_transit_map result ==="

# 1. Capture final screenshot
DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# 2. Define Paths
DRAWIO_FILE="/home/ga/Desktop/dc_metro_map.drawio"
PNG_FILE="/home/ga/Desktop/dc_metro_map.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Check File Existence and Timestamps
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED_AFTER_START="false"

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# 4. Deep Analysis using Python
# This script parses the draw.io XML (handling compression) and counts:
# - Vertices (Shapes)
# - Edges (Connections)
# - Unique Colors used in edges
# - Specific Station Names found in text labels
python3 << 'PYEOF' > /tmp/metro_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/dc_metro_map.drawio"
result = {
    "num_shapes": 0,
    "num_edges": 0,
    "unique_edge_colors": 0,
    "stations_found": [],
    "termini_found": [],
    "interchanges_found": [],
    "legend_found": False,
    "error": None
}

# List of required stations to look for (normalized lower case)
REQUIRED_STATIONS = [
    "shady grove", "bethesda", "dupont circle", "farragut north", "metro center",
    "gallery place", "union station", "fort totten", "silver spring", "glenmont",
    "vienna", "ballston", "rosslyn", "foggy bottom", "farragut west", "federal triangle",
    "smithsonian", "l'enfant plaza", "eastern market", "stadium-armory", "new carrollton",
    "ashburn", "tysons", "largo", "franconia", "pentagon", "arlington cemetery",
    "capitol south", "huntington", "archives", "mt vernon sq", "branch ave",
    "anacostia", "navy yard", "college park", "greenbelt"
]

TERMINI = [
    "shady grove", "glenmont", "vienna", "new carrollton", "ashburn", "largo",
    "franconia", "huntington", "branch ave", "greenbelt", "mt vernon sq"
]

INTERCHANGES = ["metro center", "gallery place", "l'enfant plaza", "rosslyn", "fort totten", "pentagon"]

# Helper to decompress draw.io data
def decompress_diagram(content):
    if not content or not content.strip():
        return None
    try:
        # Try raw deflate
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except Exception:
        pass
    try:
        # Try URL decoding
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

        # Handle compressed diagram content
        all_cells = []
        diagrams = root.findall('.//diagram')
        for diag in diagrams:
            # Inline cells
            cells = list(diag.iter('mxCell'))
            if cells:
                all_cells.extend(cells)
            else:
                # Compressed content
                inner_root = decompress_diagram(diag.text or '')
                if inner_root is not None:
                    all_cells.extend(list(inner_root.iter('mxCell')))
        
        # Fallback for uncompressed root
        for cell in root.iter('mxCell'):
            if cell not in all_cells:
                all_cells.append(cell)

        # Analyze cells
        found_colors = set()
        found_labels = set()
        
        for cell in all_cells:
            val = (cell.get('value') or '').lower()
            style = (cell.get('style') or '').lower()
            
            # Extract color from style (strokeColor or fillColor)
            # Regex for hex codes
            colors = re.findall(r'color=(#[0-9a-f]{6})', style)
            if not colors:
                 colors = re.findall(r'color=(#[0-9a-f]{3})', style)
            for c in colors:
                found_colors.add(c)
                
            # Classify as Vertex or Edge
            if cell.get('vertex') == '1':
                result["num_shapes"] += 1
                if val:
                    # Clean label (remove HTML)
                    clean_val = re.sub(r'<[^>]+>', ' ', val).strip()
                    found_labels.add(clean_val)
                    
            elif cell.get('edge') == '1':
                result["num_edges"] += 1

        # Check for Legend (simple heuristic: vertex with "Legend" or list of lines)
        for label in found_labels:
            if "legend" in label or ("red line" in label and "blue line" in label):
                result["legend_found"] = True

        # Match Found Labels against Requirements
        # Use partial matching because "Shady Grove Station" should match "shady grove"
        for label in found_labels:
            for req in REQUIRED_STATIONS:
                if req in label and req not in result["stations_found"]:
                    result["stations_found"].append(req)
            
            for term in TERMINI:
                if term in label and term not in result["termini_found"]:
                    result["termini_found"].append(term)
                    
            for inter in INTERCHANGES:
                if inter in label and inter not in result["interchanges_found"]:
                    result["interchanges_found"].append(inter)

        result["unique_edge_colors"] = len(found_colors)
        
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 5. Create Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/metro_analysis.json || echo "{}"),
    "timestamp": "$(date -Iseconds)"
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