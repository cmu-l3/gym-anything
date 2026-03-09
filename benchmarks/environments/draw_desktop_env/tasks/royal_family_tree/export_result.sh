#!/bin/bash
# Export script for royal_family_tree task

echo "=== Exporting royal_family_tree result ==="

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/royal_task_end.png 2>/dev/null || true

# 2. Define paths
DRAWIO_FILE="/home/ga/Desktop/royal_family_tree.drawio"
PNG_FILE="/home/ga/Desktop/royal_family_tree.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Check file existence and timestamps
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
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# 4. Analyze Diagram Content using Python
# This script handles draw.io's compressed XML format and extracts semantic info
python3 << 'PYEOF' > /tmp/royal_analysis.json 2>/dev/null || true
import json
import base64
import zlib
import re
import os
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/royal_family_tree.drawio"

result = {
    "num_shapes": 0,
    "num_edges": 0,
    "num_pages": 0,
    "member_names_found": [],
    "years_found_count": 0,
    "distinct_edge_styles": False,
    "generations_detected": 0,
    "dashed_edges": 0,
    "solid_edges": 0,
    "error": None
}

EXPECTED_NAMES = [
    "Elizabeth", "Philip", "Charles", "Camilla", "Anne", "Timothy",
    "Andrew", "Sarah", "Edward", "Sophie", "William", "Catherine",
    "Harry", "Meghan", "Peter", "Zara", "Beatrice", "Eugenie",
    "Louise", "James", "George", "Charlotte", "Louis", "Archie", "Lilibet"
]

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
        # Try URL encoded
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'):
            return ET.fromstring(decoded_str)
    except Exception:
        pass
    return None

try:
    if os.path.exists(filepath):
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Count pages
        diagrams = root.findall('diagram')
        result["num_pages"] = len(diagrams)
        
        all_cells = []
        
        # Process pages to get cells
        for diag in diagrams:
            # Inline
            cells = list(diag.iter('mxCell'))
            if cells:
                all_cells.extend(cells)
            else:
                # Compressed
                inner = decompress_diagram(diag.text)
                if inner is not None:
                    all_cells.extend(list(inner.iter('mxCell')))
        
        # Fallback to root cells
        if not all_cells:
            all_cells = list(root.iter('mxCell'))

        # Analyze cells
        y_coords = []
        
        for cell in all_cells:
            val = (cell.get('value') or '').strip()
            style = (cell.get('style') or '').lower()
            geo = cell.find('mxGeometry')
            
            # Vertices (Shapes)
            if cell.get('vertex') == '1':
                result["num_shapes"] += 1
                
                # Check for names
                # Remove HTML tags for text checking
                plain_text = re.sub(r'<[^>]+>', ' ', val).replace('&nbsp;', ' ')
                for name in EXPECTED_NAMES:
                    if name.lower() in plain_text.lower() and name not in result["member_names_found"]:
                        result["member_names_found"].append(name)
                
                # Check for years (4 digits starting with 19 or 20)
                if re.search(r'\b(19|20)\d{2}\b', plain_text):
                    result["years_found_count"] += 1
                    
                # Collect Y coords for generation analysis
                if geo is not None:
                    try:
                        y = float(geo.get('y'))
                        y_coords.append(y)
                    except (ValueError, TypeError):
                        pass

            # Edges (Connectors)
            elif cell.get('edge') == '1':
                result["num_edges"] += 1
                if 'dashed=1' in style or 'dashpattern' in style:
                    result["dashed_edges"] += 1
                else:
                    result["solid_edges"] += 1

        # Generational Analysis (clustering Y coordinates)
        if y_coords:
            y_coords.sort()
            clusters = []
            if len(y_coords) > 0:
                current_cluster = [y_coords[0]]
                for y in y_coords[1:]:
                    if y - current_cluster[-1] < 100: # 100px tolerance for same row
                        current_cluster.append(y)
                    else:
                        clusters.append(current_cluster)
                        current_cluster = [y]
                clusters.append(current_cluster)
            
            # Filter out tiny clusters (noise)
            significant_clusters = [c for c in clusters if len(c) >= 2]
            result["generations_detected"] = len(significant_clusters)
            
        if result["dashed_edges"] > 0 and result["solid_edges"] > 0:
            result["distinct_edge_styles"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 5. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/royal_analysis.json 2>/dev/null || echo "{}")
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="