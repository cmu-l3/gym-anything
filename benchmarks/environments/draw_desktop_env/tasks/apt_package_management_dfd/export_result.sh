#!/bin/bash
# Do NOT use set -e

echo "=== Exporting apt_package_management_dfd result ==="

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Define paths
DRAWIO_FILE="/home/ga/Desktop/apt_dfd.drawio"
PNG_FILE="/home/ga/Desktop/apt_dfd.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check file existence and timestamps
FILE_EXISTS="false"
FILE_MODIFIED_AFTER_START="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
fi

# 4. Deep Analysis using Python (Handles XML parsing and Keyword extraction)
# We embed this python script to run inside the container environment
python3 << 'PYEOF' > /tmp/apt_dfd_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/apt_dfd.drawio"
result = {
    "num_pages": 0,
    "num_shapes": 0,
    "num_processes": 0,
    "num_datastores": 0,
    "num_entities": 0,
    "num_edges": 0,
    "keywords_found": [],
    "text_content": "",
    "error": None
}

# Keywords to look for
KEYWORDS = [
    "parse", "fetch", "resolve", "download", "verify", "install",
    "sources", "list", "cache", "dpkg", "status",
    "admin", "repository", "key", "gpg"
]

def decompress_diagram(content):
    """Decompress draw.io content (deflate)"""
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

        # Count pages
        pages = root.findall('.//diagram')
        result["num_pages"] = len(pages)

        all_cells = []
        for page in pages:
            # Try inline first
            cells = list(page.iter('mxCell'))
            if cells:
                all_cells.extend(cells)
            else:
                # Try compressed
                inner = decompress_diagram(page.text)
                if inner:
                    all_cells.extend(list(inner.iter('mxCell')))
        
        # Fallback for uncompressed flat files
        if not all_cells:
            all_cells = list(root.iter('mxCell'))

        all_text = []
        
        for cell in all_cells:
            val = str(cell.get('value') or '').lower()
            style = str(cell.get('style') or '').lower()
            
            # Skip noise
            if not val and not style: continue
            
            # Collect text for keyword search
            if val:
                import html
                clean_val = re.sub(r'<[^>]+>', ' ', val)
                clean_val = html.unescape(clean_val).strip()
                all_text.append(clean_val)

            # Classify shapes based on style
            if cell.get('vertex') == '1':
                result["num_shapes"] += 1
                
                # Processes: Ellipse
                if 'ellipse' in style:
                    result["num_processes"] += 1
                # Data Stores: Cylinder or open rect or specifically named
                elif 'shape=cylinder' in style or 'datastore' in style or 'partialrectangle' in style:
                    result["num_datastores"] += 1
                # External Entities: Rectangles (default or explicit)
                # Note: This is loose because draw.io default rect style string varies
                elif 'shape=rect' in style or ('rounded=0' in style and 'ellipse' not in style):
                    result["num_entities"] += 1
                    
            # Edges
            if cell.get('edge') == '1':
                result["num_edges"] += 1

        # Keyword matching
        full_text = " ".join(all_text).lower()
        result["text_content"] = full_text[:2000] # Debug sample
        
        for kw in KEYWORDS:
            if kw in full_text:
                result["keywords_found"].append(kw)

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# 5. Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Merge Python analysis into JSON
if [ -f /tmp/apt_dfd_analysis.json ]; then
    jq -s '.[0] * .[1]' "$TEMP_JSON" /tmp/apt_dfd_analysis.json > /tmp/task_result.json
else
    mv "$TEMP_JSON" /tmp/task_result.json
fi

# Cleanup
rm -f "$TEMP_JSON" /tmp/apt_dfd_analysis.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="