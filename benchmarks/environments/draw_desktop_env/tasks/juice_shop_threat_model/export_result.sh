#!/bin/bash
# export_result.sh for juice_shop_threat_model

echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Desktop/juice_shop_threat_model.drawio"
PNG_FILE="/home/ga/Desktop/juice_shop_threat_model.png"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existence and timestamps
FILE_EXISTS="false"
FILE_MODIFIED_AFTER_START="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DRAWIO_FILE")
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE")
fi

# Python script to parse the .drawio file (XML analysis)
# This extracts shape labels, counts edges, checks for dashed boundaries, and STRIDE keywords
python3 << 'EOF' > /tmp/drawio_analysis.json
import sys
import os
import json
import zlib
import base64
import re
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/juice_shop_threat_model.drawio"
result = {
    "num_pages": 0,
    "num_shapes": 0,
    "num_edges": 0,
    "labels": [],
    "dashed_containers": 0,
    "stride_keywords_found": [],
    "text_content": ""
}

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Count pages
        diagrams = root.findall('diagram')
        result["num_pages"] = len(diagrams)
        
        all_xml_content = ""

        # Decode content from pages (handle compressed vs uncompressed)
        for diag in diagrams:
            raw_text = diag.text if diag.text else ""
            decoded_xml = ""
            
            # Try plain XML
            if raw_text.strip().startswith("<"):
                decoded_xml = raw_text
            else:
                # Try inflate
                try:
                    decoded_data = base64.b64decode(raw_text)
                    decoded_xml = zlib.decompress(decoded_data, -15).decode('utf-8')
                except:
                    # Try URL decode
                    try:
                        decoded_xml = unquote(raw_text)
                    except:
                        pass
            
            # If we decoded something, use it; otherwise fallback to file structure if uncompressed
            if decoded_xml and decoded_xml.startswith("<"):
                try:
                    # Wrap in root if needed or parse directly
                    # Usually diagram content is inside <mxGraphModel>
                    all_xml_content += decoded_xml
                except:
                    pass
        
        # If the file is uncompressed XML, we can iterate root directly
        # But draw.io often wraps pages. Let's try to parse the aggregate string 
        # or fall back to parsing the file root if pages were empty/unparseable
        
        # Simple regex-based extraction is often more robust for verification 
        # than strict XML parsing on potentially malformed fragments
        
        # 1. Extract Labels (value="...")
        # We look for value attributes in the original file and decoded content
        full_text = open(filepath, 'r').read() + all_xml_content
        
        # Clean up HTML entities
        full_text = full_text.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
        
        # Find labels
        labels = re.findall(r'value="([^"]*)"', full_text)
        clean_labels = []
        for l in labels:
            # Remove HTML tags
            clean = re.sub(r'<[^>]+>', ' ', l).strip()
            if clean:
                clean_labels.append(clean)
        result["labels"] = clean_labels
        result["text_content"] = " ".join(clean_labels).lower()
        
        # 2. Count Shapes (vertex="1")
        result["num_shapes"] = full_text.count('vertex="1"')
        
        # 3. Count Edges (edge="1")
        result["num_edges"] = full_text.count('edge="1"')
        
        # 4. Check for Dashed Containers (style contains dashed=1)
        # Regex for style attributes containing dashed
        dashed_styles = re.findall(r'style="[^"]*dashed=1[^"]*"', full_text)
        result["dashed_containers"] = len(dashed_styles)
        
        # 5. Check STRIDE keywords
        stride_cats = ["spoofing", "tampering", "repudiation", "information disclosure", "denial of service", "elevation of privilege"]
        found_cats = []
        lower_text = result["text_content"]
        for cat in stride_cats:
            if cat in lower_text:
                found_cats.append(cat)
            elif cat == "denial of service" and "dos" in lower_text: # Abbreviation check
                found_cats.append(cat)
        result["stride_keywords_found"] = found_cats

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
EOF

# Merge results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/drawio_analysis.json)
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="