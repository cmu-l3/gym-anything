#!/bin/bash
# Do NOT use set -e

echo "=== Exporting datacenter_rack_elevation result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/rack_task_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/rack_elevation.drawio"
PNG_FILE="/home/ga/Desktop/rack_elevation.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check file existence and timestamps
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
    echo "Found .drawio file: $DRAWIO_FILE ($FILE_SIZE bytes)"
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
    echo "Found .png file: $PNG_FILE ($PNG_SIZE bytes)"
fi

# Deep analysis of the draw.io file using Python
# This handles the XML parsing, decompression (if needed), and content extraction
python3 << 'PYEOF' > /tmp/rack_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/rack_elevation.drawio"
result = {
    "num_shapes": 0,
    "hostnames_found": [],
    "vendor_keywords": [],
    "distinct_colors": 0,
    "has_title": False,
    "has_legend": False,
    "rack_id_found": False,
    "error": None
}

TARGET_HOSTNAMES = [
    "sw-tor-a", "sw-tor-b", "web01", "web02", "app01", "app02",
    "db-primary", "db-replica", "ups-a", "ups-b"
]

VENDOR_KEYS = ["cisco", "catalyst", "dell", "poweredge", "apc", "smart-ups", "srt"]

def decompress_diagram(content):
    if not content or not content.strip():
        return None
    try:
        # draw.io typically uses raw deflate without header (-15)
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
        # Handle diagrams (pages)
        diagrams = root.findall('diagram')
        if not diagrams:
            # Fallback for uncompressed simple XML
            all_cells = list(root.iter('mxCell'))
        else:
            for d in diagrams:
                if d.text and d.text.strip():
                    xml_root = decompress_diagram(d.text)
                    if xml_root is not None:
                        all_cells.extend(list(xml_root.iter('mxCell')))
                    else:
                        # Maybe uncompressed inside diagram tag?
                        all_cells.extend(list(d.iter('mxCell')))
                else:
                    # Check for inline graph model
                    all_cells.extend(list(d.iter('mxCell')))

        # Extract text and styles
        all_text = []
        colors = set()
        
        for cell in all_cells:
            val = (cell.get('value') or '').strip()
            style = (cell.get('style') or '').lower()
            
            # Skip root cells
            if cell.get('id') in ('0', '1'):
                continue
                
            # Count visible shapes
            if cell.get('vertex') == '1':
                result["num_shapes"] += 1
                
                # Check for fill colors
                fill_match = re.search(r'fillcolor=([^;]+)', style)
                if fill_match:
                    c = fill_match.group(1).lower()
                    if c != 'none' and c != '#ffffff' and c != 'white':
                        colors.add(c)

            # Strip HTML from label
            clean_val = re.sub(r'<[^>]+>', ' ', val).lower()
            if clean_val:
                all_text.append(clean_val)

        full_text = " ".join(all_text)
        result["distinct_colors"] = len(colors)

        # Check hostnames
        for host in TARGET_HOSTNAMES:
            if host in full_text:
                result["hostnames_found"].append(host)

        # Check vendor keywords
        for k in VENDOR_KEYS:
            if k in full_text:
                result["vendor_keywords"].append(k)

        # Check specific strings
        if "rk-nyc-042" in full_text:
            result["rack_id_found"] = True
        
        if "nyc-dc1" in full_text or "row 7" in full_text:
            result["has_title"] = True
            
        if "legend" in full_text:
            result["has_legend"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/rack_analysis.json 2>/dev/null || echo "{}")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json