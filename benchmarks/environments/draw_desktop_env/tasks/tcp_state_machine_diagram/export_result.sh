#!/bin/bash
# export_result.sh for tcp_state_machine_diagram

echo "=== Exporting TCP State Machine Result ==="

# 1. Capture final screenshot
DISPLAY=:1 import -window root /tmp/tcp_task_end.png 2>/dev/null || true

# 2. File paths
DRAWIO_FILE="/home/ga/Desktop/tcp_state_machine.drawio"
PNG_FILE="/home/ga/Desktop/tcp_state_machine.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Check File Existence & Timestamp
FILE_EXISTS="false"
FILE_MODIFIED_AFTER_START="false"
PNG_EXISTS="false"
PNG_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE")
fi

# 4. Python Analysis Script
# This script parses the .drawio XML to count states, edges, pages, and colors.
python3 << 'PYEOF' > /tmp/tcp_analysis.json 2>/dev/null || true
import json
import re
import os
import base64
import zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/tcp_state_machine.drawio"
result = {
    "num_states": 0,
    "num_transitions": 0,
    "found_states": [],
    "found_keywords": [],
    "num_pages": 0,
    "has_happy_path": False,
    "has_legend": False,
    "colors_used": set(),
    "valid_xml": False,
    "error": None
}

REQUIRED_STATES = [
    "CLOSED", "LISTEN", "SYN_SENT", "SYN_RECEIVED", "ESTABLISHED",
    "FIN_WAIT_1", "FIN_WAIT_2", "CLOSE_WAIT", "CLOSING", "LAST_ACK", "TIME_WAIT"
]

TRANSITION_KEYWORDS = ["SYN", "ACK", "FIN", "RST", "CLOSE", "OPEN", "TIMEOUT", "RECV", "SEND"]

def decode_drawio_content(content):
    # draw.io files can be plain XML or compressed (Deflate+Base64)
    if not content: return None
    try:
        # Try raw XML first
        if content.strip().startswith('<'):
            return ET.fromstring(content)
    except: pass
    
    try:
        # Try Base64+Deflate
        decoded = base64.b64decode(content)
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except: pass
    
    try:
        # Try URL decoding
        from urllib.parse import unquote
        decoded = unquote(content)
        if decoded.strip().startswith('<'):
            return ET.fromstring(decoded)
    except: pass
    
    return None

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        result["valid_xml"] = True
        
        # Count pages
        diagrams = root.findall('diagram')
        result["num_pages"] = len(diagrams)
        
        for diag in diagrams:
            name = diag.get('name', '').lower()
            if 'happy' in name or 'path' in name:
                result["has_happy_path"] = True
                
            # Content might be inline or text-node
            root_cell = None
            if diag.find('mxGraphModel'):
                root_cell = diag.find('mxGraphModel').find('root')
            elif diag.text:
                graph_model = decode_drawio_content(diag.text)
                if graph_model is not None:
                    root_cell = graph_model.find('root')
            
            if root_cell is not None:
                for cell in root_cell.iter('mxCell'):
                    val = (cell.get('value') or '').upper()
                    style = (cell.get('style') or '')
                    
                    # Check vertices (States)
                    if cell.get('vertex') == '1':
                        # Clean label (remove HTML)
                        clean_val = re.sub(r'<[^>]+>', ' ', val).strip()
                        clean_val = clean_val.replace('-', '_').replace(' ', '_')
                        
                        # Match against required states
                        for req in REQUIRED_STATES:
                            normalized_req = req.replace('-', '_')
                            if normalized_req in clean_val:
                                if req not in result["found_states"]:
                                    result["found_states"].append(req)
                        
                        # Check for Legend
                        if "LEGEND" in clean_val or "KEY" in clean_val:
                            result["has_legend"] = True
                            
                    # Check edges (Transitions)
                    elif cell.get('edge') == '1':
                        result["num_transitions"] += 1
                        
                        # Check labels for keywords
                        clean_val = re.sub(r'<[^>]+>', ' ', val).upper()
                        for kw in TRANSITION_KEYWORDS:
                            if kw in clean_val and kw not in result["found_keywords"]:
                                result["found_keywords"].append(kw)
                        
                        # Extract colors from style
                        # strokeColor=#FF0000 or strokeColor=red
                        color_match = re.search(r'strokeColor=([^;]+)', style)
                        if color_match:
                            color = color_match.group(1).lower()
                            if color not in ['none', 'default']:
                                result["colors_used"].add(color)

    except Exception as e:
        result["error"] = str(e)

# Convert set to list for JSON serialization
result["colors_used"] = list(result["colors_used"])
print(json.dumps(result))
PYEOF

# 5. Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/tcp_analysis.json || echo "{}")
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="