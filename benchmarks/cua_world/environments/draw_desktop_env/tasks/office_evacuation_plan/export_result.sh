#!/bin/bash
# Do NOT use set -e

echo "=== Exporting office_evacuation_plan result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/evac_task_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/evacuation_plan.drawio"
PNG_FILE="/home/ga/Desktop/evacuation_plan.png"

# File checks
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED_AFTER_START="false"
PNG_EXISTS="false"
PNG_SIZE=0
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# Run Python analysis script
python3 << 'PYEOF' > /tmp/evac_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/evacuation_plan.drawio"
result = {
    "rooms_found": [],
    "symbols_found": [],
    "green_edges": 0,
    "dashed_edges": 0,
    "legend_found": False,
    "assembly_point": False,
    "text_content": ""
}

ROOMS = ["reception", "workspace", "conference", "kitchen", "server"]
SYMBOLS = ["extinguisher", "alarm", "exit", "fire"]

def decompress_diagram(content):
    if not content or not content.strip(): return None
    try:
        decoded = base64.b64decode(content.strip())
        return ET.fromstring(zlib.decompress(decoded, -15))
    except: pass
    try:
        from urllib.parse import unquote
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'): return ET.fromstring(decoded_str)
    except: pass
    return None

try:
    if os.path.exists(filepath):
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        all_cells = []
        # Handle pages / compression
        pages = root.findall('.//diagram')
        for page in pages:
            inline = list(page.iter('mxCell'))
            if inline: all_cells.extend(inline)
            else:
                decomp = decompress_diagram(page.text or '')
                if decomp: all_cells.extend(list(decomp.iter('mxCell')))
        
        # Handle uncompressed root
        for cell in root.iter('mxCell'):
            if cell not in all_cells: all_cells.append(cell)
            
        # Analysis
        all_text = []
        for cell in all_cells:
            val = (cell.get('value') or '').lower()
            style = (cell.get('style') or '').lower()
            
            # Clean HTML from value
            clean_val = re.sub(r'<[^>]+>', ' ', val).strip()
            if clean_val: all_text.append(clean_val)
            
            # Check Rooms
            for r in ROOMS:
                if r in clean_val and r not in result["rooms_found"]:
                    result["rooms_found"].append(r)
            
            # Check Symbols (in value or style)
            # e.g. style="shape=mxgraph.signs.fire.fire_extinguisher"
            for s in SYMBOLS:
                if (s in clean_val or s in style) and s not in result["symbols_found"]:
                    result["symbols_found"].append(s)
            
            # Check Assembly Point
            if "assembly" in clean_val or "parking" in clean_val:
                result["assembly_point"] = True
                
            # Check Legend
            if "legend" in clean_val or "key" in clean_val:
                result["legend_found"] = True
            
            # Check Edges (Green & Dashed)
            if cell.get('edge') == '1':
                # Green check: strokeColor=#00FF00 or similar
                if 'strokecolor' in style:
                    # extract color code
                    color_match = re.search(r'strokecolor=([^;]+)', style)
                    if color_match:
                        c = color_match.group(1).lower()
                        # specific green codes or word 'green'
                        if c == 'green' or c == '#00ff00' or c == '#008000' or c == '#009900':
                            result["green_edges"] += 1
                
                # Dashed check
                if 'dashed=1' in style:
                    result["dashed_edges"] += 1

        result["text_content"] = " ".join(all_text)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/evac_analysis.json)
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"