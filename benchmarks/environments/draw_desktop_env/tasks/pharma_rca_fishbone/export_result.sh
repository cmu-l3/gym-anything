#!/bin/bash
# Do NOT use set -e to allow robust error handling

echo "=== Exporting pharma_rca_fishbone result ==="

# Paths
DRAWIO_FILE="/home/ga/Desktop/rca_fishbone.drawio"
PNG_FILE="/home/ga/Desktop/rca_fishbone.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check file existence and timestamps
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$DRAWIO_FILE")
    FILE_MTIME=$(stat -c%Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c%s "$PNG_FILE")
fi

# Parse XML content using Python
# We extract shape counts, edge counts, page counts, and all text content for verification
python3 << 'PYEOF' > /tmp/drawio_analysis.json 2>/dev/null || true
import json
import os
import sys
import xml.etree.ElementTree as ET
import base64
import zlib
import re

filepath = "/home/ga/Desktop/rca_fishbone.drawio"
result = {
    "num_shapes": 0,
    "num_edges": 0,
    "num_pages": 0,
    "text_content": [],
    "categories_found": [],
    "page_names": []
}

def decode_drawio(content):
    """Decode base64+deflate content if present"""
    if not content: return None
    try:
        # Check if it looks like XML directly
        if content.strip().startswith("<"):
            return ET.fromstring(content)
        # Try base64 decode
        decoded = base64.b64decode(content)
        # Try inflate
        try:
            decompressed = zlib.decompress(decoded, -15)
        except:
            decompressed = zlib.decompress(decoded)
        # URL decode might be needed if raw string
        return ET.fromstring(decompressed)
    except Exception as e:
        return None

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Count pages
        diagrams = root.findall('diagram')
        result['num_pages'] = len(diagrams)
        
        all_text = []
        
        # Iterate through pages
        for diagram in diagrams:
            page_name = diagram.get('name', '')
            result['page_names'].append(page_name)
            
            # Get content
            mxGraphModel = diagram.find('mxGraphModel')
            if mxGraphModel is None:
                # Content might be compressed in text of diagram tag
                mxGraphModel = decode_drawio(diagram.text)
            
            if mxGraphModel is not None:
                root_cell = mxGraphModel.find('root')
                if root_cell is not None:
                    for cell in root_cell.findall('mxCell'):
                        # Count shapes
                        if cell.get('vertex') == '1':
                            result['num_shapes'] += 1
                            val = cell.get('value', '')
                            if val: all_text.append(val)
                        # Count edges
                        if cell.get('edge') == '1':
                            result['num_edges'] += 1
                            val = cell.get('value', '')
                            if val: all_text.append(val)

        # Normalize text for analysis (strip HTML)
        clean_text = []
        for t in all_text:
            # Remove HTML tags
            t = re.sub('<[^<]+?>', ' ', t)
            # Remove non-alphanumeric (keep spaces)
            clean_text.append(t.lower())
            
        result['text_content'] = clean_text
        
        # Check categories
        categories = ["manpower", "machine", "method", "material", "measurement", "milieu"]
        full_text_str = " ".join(clean_text)
        for cat in categories:
            if cat in full_text_str:
                result['categories_found'].append(cat)

    except Exception as e:
        result['error'] = str(e)

print(json.dumps(result))
PYEOF

# Combine results
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "timestamp": "$(date -Iseconds)",
    "analysis": $(cat /tmp/drawio_analysis.json 2>/dev/null || echo "{}")
}
EOF

# Clean up temp
rm -f /tmp/drawio_analysis.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="