#!/bin/bash
# Do NOT use set -e

echo "=== Exporting ecommerce_wardley_map result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/marketplace_wardley_map.drawio"
PNG_FILE="/home/ga/Desktop/marketplace_wardley_map.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check files
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0
if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# Parse the draw.io XML (handling compression)
python3 << 'PYEOF' > /tmp/wardley_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/marketplace_wardley_map.drawio"
result = {
    "num_shapes": 0,
    "num_edges": 0,
    "num_pages": 0,
    "labels_found": [],
    "axis_labels_found": [],
    "has_title": False,
    "has_second_page_content": False,
    "x_distribution": [],
    "error": None
}

EXPECTED_COMPONENTS = [
    "customer", "buyer experience", "seller experience", "search", "discovery",
    "product listings", "checkout", "dashboard", "ratings", "reviews",
    "recommendation", "fraud", "order management", "payment", "notification",
    "analytics", "compute", "storage", "cdn", "identity", "auth"
]

AXIS_TERMS = ["genesis", "custom", "product", "commodity", "visible", "invisible"]

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

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        pages = root.findall('.//diagram')
        result["num_pages"] = len(pages)
        
        # Check second page for content
        if len(pages) > 1:
            p2_content = pages[1].text
            if p2_content and len(p2_content.strip()) > 20:
                result["has_second_page_content"] = True

        all_cells = []
        for page in pages:
            # Inline cells
            inline = list(page.iter('mxCell'))
            if inline:
                all_cells.extend(inline)
            else:
                # Compressed
                inner = decompress_diagram(page.text or '')
                if inner is not None:
                    all_cells.extend(list(inner.iter('mxCell')))

        # Root cells fallback
        for cell in root.iter('mxCell'):
            if cell not in all_cells:
                all_cells.append(cell)

        x_coords = []

        for cell in all_cells:
            val = (cell.get('value') or '').lower()
            
            # Clean HTML tags
            plain_val = re.sub(r'<[^>]+>', ' ', val).strip()
            
            # Geometry for X distribution
            geo = cell.find('mxGeometry')
            if geo is not None:
                x = geo.get('x')
                if x:
                    try:
                        x_coords.append(float(x))
                    except:
                        pass

            if cell.get('vertex') == '1' and plain_val:
                result["num_shapes"] += 1
                
                # Check for components
                for comp in EXPECTED_COMPONENTS:
                    if comp in plain_val:
                        if comp not in result["labels_found"]:
                            result["labels_found"].append(comp)
                
                # Check for axis labels
                for axis in AXIS_TERMS:
                    if axis in plain_val:
                        if axis not in result["axis_labels_found"]:
                            result["axis_labels_found"].append(axis)
                
                # Check title
                if "marketplace" in plain_val or "wardley" in plain_val:
                    result["has_title"] = True
                    
            elif cell.get('edge') == '1':
                result["num_edges"] += 1

        # Analyze X distribution (evolution stages)
        if x_coords:
            min_x = min(x_coords)
            max_x = max(x_coords)
            width = max_x - min_x
            if width > 100: # Ensure diagram isn't a single point
                zones = [0, 0, 0, 0] # 4 quarters
                for x in x_coords:
                    norm = (x - min_x) / width
                    idx = int(norm * 4)
                    if idx > 3: idx = 3
                    zones[idx] += 1
                result["x_distribution"] = zones

    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

print(json.dumps(result))
PYEOF

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/wardley_analysis.json)
}
EOF

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="