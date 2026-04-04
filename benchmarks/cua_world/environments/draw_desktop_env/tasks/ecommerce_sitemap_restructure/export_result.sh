#!/bin/bash
# Do NOT use set -e

echo "=== Exporting ecommerce_sitemap_restructure result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/sitemap_task_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/luma_sitemap.drawio"
PNG_FILE="/home/ga/Desktop/luma_sitemap.png"

FILE_EXISTS="false"
FILE_SIZE=0
PNG_EXISTS="false"
PNG_SIZE=0
FILE_MODIFIED_AFTER_START="false"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

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

# Deep XML analysis with Python
# This script parses the draw.io XML to find nodes, their text labels, and their fill colors
python3 << 'PYEOF' > /tmp/sitemap_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/luma_sitemap.drawio"
result = {
    "node_count": 0,
    "edge_count": 0,
    "nodes": [],
    "root_detected": False,
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

def get_fill_color(style_str):
    if not style_str:
        return "default"
    # Extract fillColor=#xxxxxx
    match = re.search(r'fillColor=([^;]+)', style_str)
    if match:
        color = match.group(1).lower()
        if color == 'none' or color == 'default' or color == '#ffffff':
            return "white"
        return color # Returns hex code usually
    return "default"

def clean_label(label):
    if not label:
        return ""
    # Remove HTML tags if present
    clean = re.sub(r'<[^>]+>', '', label)
    # Decode HTML entities
    import html
    clean = html.unescape(clean)
    return clean.strip().lower()

try:
    if not os.path.exists(filepath):
        result["error"] = "File not found"
    else:
        tree = ET.parse(filepath)
        root = tree.getroot()

        # Handle pages (compressed or inline)
        all_cells = []
        pages = root.findall('.//diagram')
        if not pages:
            # Maybe directly in root
            all_cells = list(root.iter('mxCell'))
        else:
            for page in pages:
                inline_cells = list(page.iter('mxCell'))
                if inline_cells:
                    all_cells.extend(inline_cells)
                else:
                    inner_root = decompress_diagram(page.text or '')
                    if inner_root is not None:
                        all_cells.extend(list(inner_root.iter('mxCell')))

        # Process cells
        for cell in all_cells:
            cid = cell.get('id')
            if cid in ['0', '1']: continue # Skip root/layer 0/1

            vertex = cell.get('vertex') == '1'
            edge = cell.get('edge') == '1'
            value = cell.get('value', '')
            style = cell.get('style', '')

            if vertex:
                result["node_count"] += 1
                label = clean_label(value)
                color = get_fill_color(style)
                
                # Check for "Home" root
                if "home" in label:
                    result["root_detected"] = True

                if label:
                    result["nodes"].append({
                        "label": label,
                        "color": color,
                        "id": cid
                    })
            elif edge:
                result["edge_count"] += 1

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED_AFTER_START,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "screenshot_path": "/tmp/sitemap_task_end.png",
    "analysis": $(cat /tmp/sitemap_analysis.json 2>/dev/null || echo "{}")
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