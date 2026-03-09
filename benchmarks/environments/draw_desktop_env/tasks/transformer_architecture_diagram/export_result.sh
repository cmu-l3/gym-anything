#!/bin/bash
echo "=== Exporting transformer_architecture_diagram results ==="

# Define paths
DRAWIO_FILE="/home/ga/Desktop/transformer_arch.drawio"
PNG_FILE="/home/ga/Desktop/transformer_arch.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check file existence and modification times
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DRAWIO_FILE")
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE")
fi

# 2. Python script to parse the draw.io XML (handling compression)
# and count components
python3 << 'EOF' > /tmp/drawio_analysis.json
import json
import base64
import zlib
import re
import os
import sys
from urllib.parse import unquote
import xml.etree.ElementTree as ET

file_path = "/home/ga/Desktop/transformer_arch.drawio"
result = {
    "xml_parsed": False,
    "counts": {
        "Multi-Head Attention": 0,
        "Masked": 0,
        "Feed Forward": 0,
        "Add & Norm": 0,
        "Linear": 0,
        "Softmax": 0,
        "Positional Encoding": 0,
        "Embedding": 0,
        "Nx": 0
    },
    "edge_count": 0,
    "text_content": ""
}

def decode_drawio_content(content):
    """Decode draw.io content which can be plain XML, URL-encoded, or Deflate-compressed."""
    if not content:
        return ""
    
    # Try raw XML first
    if content.strip().startswith("<mxGraphModel"):
        return content
        
    # Try URL decoded
    try:
        decoded = unquote(content)
        if decoded.strip().startswith("<mxGraphModel"):
            return decoded
    except:
        pass

    # Try Base64 + Deflate (standard .drawio format)
    try:
        # It's usually inside <diagram>...</diagram>
        # But if we get just the inner text:
        decoded_b64 = base64.b64decode(content)
        # -15 for raw deflate (no header)
        decompressed = zlib.decompress(decoded_b64, -15)
        return unquote(decompressed.decode('utf-8'))
    except Exception as e:
        return ""

if os.path.exists(file_path):
    try:
        # Parse the main file structure
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # draw.io files can have multiple pages, usually inside <diagram> tags
        # The content inside <diagram> is often compressed
        diagrams = root.findall('diagram')
        
        full_xml_content = ""
        
        if diagrams:
            for d in diagrams:
                full_xml_content += decode_drawio_content(d.text)
        else:
            # Maybe it's an uncompressed file or just mxGraphModel at root?
            # If root is mxfile, it might have children. 
            # If we failed to find diagram tags, let's try to convert the whole file to string
            with open(file_path, 'r') as f:
                full_xml_content = f.read()

        # Now we parse the expanded XML content to count shapes/labels
        # We look for "value" attributes in mxCell
        
        # Simple string matching on the expanded XML is often more robust 
        # than re-parsing partial XML fragments, but let's try to be precise.
        # We'll normalize text to lowercase for counting, but keep keys logic specific.
        
        content_lower = full_xml_content.lower()
        result["text_content"] = content_lower[:1000] # Debug sample
        result["xml_parsed"] = True
        
        # Count Edges
        # Edges usually have edge="1" in mxCell
        result["edge_count"] = full_xml_content.count('edge="1"')
        
        # Count Labels (heuristics based on value="" attributes)
        # We use regex to avoid counting the same string multiple times if it appears in styling
        # But simple counting is usually sufficient for "at least X" checks.
        
        target_phrases = {
            "Multi-Head Attention": ["multi-head attention", "multi head attention"],
            "Masked": ["masked"],
            "Feed Forward": ["feed forward", "feed-forward"],
            "Add & Norm": ["add & norm", "add and norm", "add&norm"],
            "Linear": ["linear"],
            "Softmax": ["softmax"],
            "Positional Encoding": ["positional encoding"],
            "Embedding": ["embedding"],
            "Nx": ["nx"]
        }
        
        for key, phrases in target_phrases.items():
            count = 0
            for phrase in phrases:
                count += content_lower.count(phrase)
            result["counts"][key] = count
            
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
EOF

# 3. Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/drawio_analysis.json)
}
EOF

mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json