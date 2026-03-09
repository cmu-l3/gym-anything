#!/bin/bash
# Export result script for windsor_family_tree

echo "=== Exporting windsor_family_tree result ==="

DISPLAY=:1 import -window root /tmp/windsor_final.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/windsor_family_tree.drawio"
PNG_FILE="/home/ga/Desktop/windsor_family_tree.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_MODIFIED="false"
PNG_EXISTS="false"
PNG_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# Analyze the draw.io XML content
python3 << 'PYEOF' > /tmp/windsor_analysis.json 2>/dev/null || true
import json
import xml.etree.ElementTree as ET
import re
import os
import base64
import zlib
from urllib.parse import unquote

filepath = "/home/ga/Desktop/windsor_family_tree.drawio"
result = {
    "vertex_count": 0,
    "edge_count": 0,
    "page_count": 0,
    "names_found": [],
    "marriage_edges_found": 0,
    "deceased_styling_found": False,
    "years_found": 0,
    "error": None
}

KEY_NAMES = [
    "George V", "Mary of Teck", "Edward VIII", "George VI", "Elizabeth Bowes-Lyon",
    "Elizabeth II", "Philip", "Charles", "Diana", "Camilla", "Anne", "Andrew", "Edward",
    "William", "Catherine", "Kate", "Harry", "Meghan", "George", "Charlotte", "Louis", "Archie"
]

def decompress_diagram(content):
    if not content or not content.strip():
        return None
    try:
        # Try raw base64 + inflate
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except Exception:
        pass
    try:
        # Try URL decoding
        decoded_str = unquote(content.strip())
        if decoded_str.strip().startswith('<'):
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
        result["page_count"] = len(diagrams) if diagrams else 1

        all_cells = []
        
        # Extract cells from all pages
        for diagram in diagrams:
            # Check for inline XML
            if diagram.find('mxGraphModel'):
                all_cells.extend(list(diagram.iter('mxCell')))
            elif diagram.text:
                # Compressed content
                graph_root = decompress_diagram(diagram.text)
                if graph_root is not None:
                    all_cells.extend(list(graph_root.iter('mxCell')))
        
        # Fallback if no diagram tags (uncompressed file)
        if not diagrams:
            all_cells = list(root.iter('mxCell'))

        text_content = ""
        styles = []

        for cell in all_cells:
            val = str(cell.get('value') or '')
            style = str(cell.get('style') or '')
            
            # Analyze Vertices (People)
            if cell.get('vertex') == '1':
                result["vertex_count"] += 1
                text_content += " " + val
                
                # Check for deceased styling (grey fill or specific marker)
                # Common grey codes: #F5F5F5, #CCCCCC, #808080, or "grey"
                if 'fillColor=#F' in style or 'fillColor=#C' in style or 'fillColor=grey' in style or 'fillColor=#808080' in style:
                    result["deceased_styling_found"] = True
                
            # Analyze Edges (Relationships)
            elif cell.get('edge') == '1':
                result["edge_count"] += 1
                
                # Check for marriage differentiation
                # Dashed lines, or double lines, or specific labels
                if 'dashed=1' in style or 'endArrow=diamond' in style or 'startArrow=diamond' in style:
                    result["marriage_edges_found"] += 1
                elif 'm.' in val.lower() or 'marri' in val.lower():
                    result["marriage_edges_found"] += 1

        # Search for key names (case insensitive)
        text_lower = text_content.lower()
        import html
        text_lower = html.unescape(text_lower) # Decode HTML entities
        
        for name in KEY_NAMES:
            # Simple substring match is usually sufficient for this task
            if name.lower() in text_lower:
                result["names_found"].append(name)
        
        # Count year patterns (4 digits starting with 18, 19, or 20)
        years = re.findall(r'\b(18|19|20)\d{2}\b', text_content)
        result["years_found"] = len(years)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final JSON result
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/windsor_analysis.json)
}
EOF

echo "Result saved to /tmp/task_result.json"