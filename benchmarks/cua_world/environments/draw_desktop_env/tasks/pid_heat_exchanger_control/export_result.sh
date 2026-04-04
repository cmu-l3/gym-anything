#!/bin/bash
# Do NOT use set -e

echo "=== Exporting pid_heat_exchanger_control result ==="

# Capture final screenshot
DISPLAY=:1 import -window root /tmp/pid_task_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/heat_exchanger_pid.drawio"
PNG_FILE="/home/ga/Desktop/heat_exchanger_pid.png"

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
    echo "Found P&ID file: $DRAWIO_FILE ($FILE_SIZE bytes)"
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
    echo "Found PNG: $PNG_FILE ($PNG_SIZE bytes)"
fi

# Python script to analyze the diagram XML
# It checks for P&ID specific shapes and the required tag text
python3 << 'PYEOF' > /tmp/pid_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/heat_exchanger_pid.drawio"
result = {
    "num_shapes": 0,
    "num_edges": 0,
    "pid_library_used": False,
    "tags_found": [],
    "text_content": "",
    "pid_shapes_count": 0,
    "error": None
}

REQUIRED_TAGS = ["hx-200", "tt-201", "tic-201", "tv-201"]

# Keywords indicating P&ID shapes in style attribute
PID_STYLE_KEYWORDS = [
    "pid", "valve", "instrument", "heat_exchanger", "sensor", 
    "pump", "tank", "vessel", "actuator"
]

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

try:
    if not os.path.exists(filepath):
        result["error"] = "File not found"
    else:
        tree = ET.parse(filepath)
        root = tree.getroot()

        # Handle potentially compressed diagram
        pages = root.findall('.//diagram')
        all_cells = []
        
        # If pages exist, process them
        for page in pages:
            # Inline
            inline = list(page.iter('mxCell'))
            if inline:
                all_cells.extend(inline)
            else:
                # Compressed
                inner = decompress_diagram(page.text or '')
                if inner is not None:
                    all_cells.extend(list(inner.iter('mxCell')))
        
        # Root level cells (uncompressed save)
        for cell in root.iter('mxCell'):
            if cell not in all_cells:
                all_cells.append(cell)

        all_text = []
        
        for cell in all_cells:
            val = (cell.get('value') or '').strip()
            style = (cell.get('style') or '').lower()
            
            # Skip background/root cells
            if cell.get('id') in ('0', '1'):
                continue

            if cell.get('vertex') == '1':
                result["num_shapes"] += 1
                if val:
                    all_text.append(val)
                
                # Check for P&ID styles
                if any(k in style for k in PID_STYLE_KEYWORDS):
                    result["pid_library_used"] = True
                    result["pid_shapes_count"] += 1
                    
            elif cell.get('edge') == '1':
                result["num_edges"] += 1
                if val:
                    all_text.append(val)

        # Normalize text for searching
        # Remove HTML tags which draw.io often uses for labels
        import html as html_mod
        combined = ' '.join(all_text).lower()
        plain = re.sub(r'<[^>]+>', ' ', combined)
        plain = html_mod.unescape(plain).lower()
        result["text_content"] = plain[:5000]

        # Search for tags
        for tag in REQUIRED_TAGS:
            # Simple check
            if tag in plain:
                result["tags_found"].append(tag)
            else:
                # Regex check for variations like "HX 200" or "HX\n200"
                parts = tag.split('-')
                if len(parts) == 2:
                    pattern = re.escape(parts[0]) + r'\s*[\-]?\s*' + re.escape(parts[1])
                    if re.search(pattern, plain):
                        result["tags_found"].append(tag)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
ANALYSIS_JSON=$(cat /tmp/pid_analysis.json)

cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $ANALYSIS_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"