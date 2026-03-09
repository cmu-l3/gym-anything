#!/bin/bash
# Do NOT use set -e

echo "=== Exporting retail_shelf_planogram result ==="

DISPLAY=:1 import -window root /tmp/planogram_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/cereal_planogram.drawio"
PNG_FILE="/home/ga/Desktop/cereal_planogram.png"

FILE_EXISTS="false"
FILE_MODIFIED="false"
PNG_EXISTS="false"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# Analyze the draw.io XML to extract product positions
# We need to determine the Y-coordinate of each product shape to verify shelf placement
python3 << 'PYEOF' > /tmp/planogram_analysis.json 2>/dev/null || true
import json, re, base64, zlib, os
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/cereal_planogram.drawio"
result = {
    "shapes_found": [],
    "title_found": False,
    "error": None
}

def decompress_diagram(content):
    if not content or not content.strip(): return None
    try:
        decoded = base64.b64decode(content.strip())
        return ET.fromstring(zlib.decompress(decoded, -15))
    except:
        pass
    try:
        from urllib.parse import unquote
        decoded = unquote(content.strip())
        if decoded.startswith('<'): return ET.fromstring(decoded)
    except:
        pass
    return None

try:
    if os.path.exists(filepath):
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Get all cells (handling compressed/uncompressed)
        all_cells = []
        diagrams = root.findall('.//diagram')
        for d in diagrams:
            inner = decompress_diagram(d.text)
            if inner is not None:
                all_cells.extend(list(inner.iter('mxCell')))
            else:
                all_cells.extend(list(d.iter('mxCell')))
        
        # Fallback to root cells
        for c in root.iter('mxCell'):
            if c not in all_cells: all_cells.append(c)
            
        # Define product keywords to look for
        products = {
            "All Bran": ["all", "bran"],
            "Muesli": ["muesli"],
            "Corn Flakes": ["corn", "flakes"],
            "Raisin Bran": ["raisin"],
            "Froot Loops": ["froot", "loops"],
            "Apple Jacks": ["apple", "jacks"],
            "Bag O' Puffs": ["bag", "puffs"],
            "Value Oats": ["value", "oats"]
        }
        
        for cell in all_cells:
            val = (cell.get('value') or '').lower()
            geo = cell.find('mxGeometry')
            
            # Check for Title
            if "planogram" in val and "bay" in val:
                result["title_found"] = True
                
            # Check for Products
            # We need the Y coordinate
            if geo is not None:
                try:
                    y = float(geo.get('y', 0))
                    # Also check relative y if nested
                    # (Simplified: assume flat structure for this task difficulty)
                    
                    found_name = None
                    for prod_name, keywords in products.items():
                        if all(k in val for k in keywords):
                            found_name = prod_name
                            break
                    
                    if found_name:
                        result["shapes_found"].append({
                            "name": found_name,
                            "y": y
                        })
                except:
                    pass

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Combine info into final result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "png_exists": $PNG_EXISTS,
    "analysis": $(cat /tmp/planogram_analysis.json 2>/dev/null || echo "{}")
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"