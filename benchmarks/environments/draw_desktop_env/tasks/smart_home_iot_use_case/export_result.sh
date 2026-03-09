#!/bin/bash
# Do NOT use set -e

echo "=== Exporting smart_home_iot_use_case result ==="

DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/securehub_usecase.drawio"
PNG_FILE="/home/ga/Desktop/securehub_usecase.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Default values
FILE_EXISTS="false"
FILE_MODIFIED="false"
PNG_EXISTS="false"

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

# Deep XML analysis with Python
# This handles the draw.io compression (deflate) and parses the XML structure
python3 << 'PYEOF' > /tmp/task_result.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/securehub_usecase.drawio"
pngpath = "/home/ga/Desktop/securehub_usecase.png"
task_start = 0
try:
    with open("/tmp/task_start_timestamp", "r") as f:
        task_start = int(f.read().strip())
except:
    pass

result = {
    "file_exists": False,
    "file_modified_after_start": False,
    "png_exists": False,
    "actors_count": 0,
    "use_cases_count": 0,
    "system_boundary_found": False,
    "includes_found": 0,
    "extends_found": 0,
    "required_terms_found": [],
    "error": None
}

if os.path.exists(pngpath):
    result["png_exists"] = True

if not os.path.exists(filepath):
    result["error"] = "File not found"
else:
    result["file_exists"] = True
    if os.path.getmtime(filepath) > task_start:
        result["file_modified_after_start"] = True

    def decompress_diagram(content):
        if not content or not content.strip():
            return None
        try:
            # Try raw inflate
            decoded = base64.b64decode(content.strip())
            decompressed = zlib.decompress(decoded, -15)
            return ET.fromstring(decompressed)
        except Exception:
            pass
        try:
            # Try URL decode
            from urllib.parse import unquote
            decoded_str = unquote(content.strip())
            if decoded_str.startswith('<'):
                return ET.fromstring(decoded_str)
        except Exception:
            pass
        return None

    try:
        tree = ET.parse(filepath)
        root = tree.getroot()

        all_cells = []
        # Check for pages
        pages = root.findall('.//diagram')
        for page in pages:
            # Try inline
            inline = list(page.iter('mxCell'))
            if inline:
                all_cells.extend(inline)
            else:
                # Try compressed
                inner = decompress_diagram(page.text or '')
                if inner is not None:
                    all_cells.extend(list(inner.iter('mxCell')))
        
        # Check root (uncompressed)
        for cell in root.iter('mxCell'):
            if cell not in all_cells:
                all_cells.append(cell)

        # Analysis
        text_content = ""
        for cell in all_cells:
            style = (cell.get('style') or '').lower()
            val = (cell.get('value') or '').lower()
            text_content += val + " "

            # Actors
            if 'umlactor' in style or 'shape=actor' in style:
                result["actors_count"] += 1
            
            # Use Cases (Ellipses)
            # Exclude actors (which might use ellipses in some libs) and tiny markers
            elif 'ellipse' in style and 'umlactor' not in style and 'endarrow' not in style:
                result["use_cases_count"] += 1
            
            # Relationships
            if 'endarrow' in style or 'edge=1' in str(cell.attrib):
                if 'dashed=1' in style:
                    if 'include' in val or '&lt;&lt;include&gt;&gt;' in val:
                        result["includes_found"] += 1
                    if 'extend' in val or '&lt;&lt;extend&gt;&gt;' in val:
                        result["extends_found"] += 1
            
            # Boundary (Group/Swimlane/Rect with no fill or specific style)
            if ('swimlane' in style or 'group' in style or 'container' in style) and 'umlactor' not in style:
                result["system_boundary_found"] = True

        # Check for terms
        req_terms = ["homeowner", "guest", "emergency", "cloud", "unlock", "camera", "panic", "arm", "disarm"]
        for term in req_terms:
            if term in text_content:
                result["required_terms_found"].append(term)

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

cat /tmp/task_result.json
echo "=== Export complete ==="