#!/bin/bash
# Do NOT use set -e

echo "=== Exporting haber_process_pfd result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/haber_process.drawio"
PNG_FILE="/home/ga/Desktop/haber_process.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check Files Existence and Timestamps
FILE_EXISTS="false"
PNG_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# 2. Analyze Diagram Content using Python
# This script parses the XML (handling compression) and checks for:
# - Shape count
# - Edge count
# - Use of PID/ProcEng libraries
# - Specific text labels (NH3, Reactor, etc.)
python3 << 'PYEOF' > /tmp/pfd_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/haber_process.drawio"
result = {
    "num_shapes": 0,
    "num_edges": 0,
    "has_pid_shapes": False,
    "found_keywords": [],
    "has_recycle_text": False,
    "text_content": ""
}

REQUIRED_KEYWORDS = ["compressor", "reactor", "separator", "condenser", "cooler", "heater", "exchanger", "ammonia", "nh3", "n2", "h2", "feed"]

def decompress_diagram(content):
    if not content or not content.strip(): return None
    try:
        # Try raw deflate
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except:
        pass
    try:
        # Try URL decoding (sometimes used)
        from urllib.parse import unquote
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'):
            return ET.fromstring(decoded_str)
    except:
        pass
    return None

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Handle compressed diagram data
        all_cells = []
        diagrams = root.findall('diagram')
        for diag in diagrams:
            inner_root = decompress_diagram(diag.text)
            if inner_root:
                all_cells.extend(list(inner_root.iter('mxCell')))
            else:
                # Maybe uncompressed inside diagram tag?
                all_cells.extend(list(diag.iter('mxCell')))
        
        # Also check root for uncompressed direct children
        for cell in root.iter('mxCell'):
            if cell not in all_cells:
                all_cells.append(cell)

        text_parts = []
        
        for cell in all_cells:
            val = (cell.get('value') or '').strip()
            style = (cell.get('style') or '').lower()
            
            # Skip background/root cells
            if cell.get('id') in ['0', '1']: continue

            if cell.get('vertex') == '1':
                result["num_shapes"] += 1
                if val: text_parts.append(val)
                
                # Check for PID library usage
                # Common indicators: 'pid', 'chemical', 'proceng', specific shape names like 'mxgraph.pid...'
                if 'pid' in style or 'chemical' in style or 'proceng' in style or 'mxgraph.pid' in style:
                    result["has_pid_shapes"] = True
                    
            elif cell.get('edge') == '1':
                result["num_edges"] += 1
                if val: text_parts.append(val)

        # Normalize text
        combined_text = " ".join(text_parts).lower()
        
        # Clean HTML tags
        clean_text = re.sub(r'<[^>]+>', ' ', combined_text)
        result["text_content"] = clean_text

        # Check keywords
        for kw in REQUIRED_KEYWORDS:
            if kw in clean_text:
                result["found_keywords"].append(kw)
        
        if "recycle" in clean_text:
            result["has_recycle_text"] = True

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "png_exists": $PNG_EXISTS,
    "file_modified": $FILE_MODIFIED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "analysis": $(cat /tmp/pfd_analysis.json 2>/dev/null || echo "{}")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="