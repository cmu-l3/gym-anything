#!/bin/bash
echo "=== Exporting python_release_timeline results ==="

# Record end time and load start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_SHAPE_COUNT=$(cat /tmp/initial_shape_count.txt 2>/dev/null || echo "0")

DIAGRAM_FILE="/home/ga/Diagrams/python_timeline.drawio"
PDF_FILE="/home/ga/Diagrams/exports/python_timeline.pdf"

# 1. Take final screenshot (Visual Evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamps
DIAGRAM_EXISTS="false"
DIAGRAM_MODIFIED="false"
if [ -f "$DIAGRAM_FILE" ]; then
    DIAGRAM_EXISTS="true"
    MTIME=$(stat -c %Y "$DIAGRAM_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        DIAGRAM_MODIFIED="true"
    fi
fi

PDF_EXISTS="false"
PDF_MODIFIED="false"
if [ -f "$PDF_FILE" ] && [ -s "$PDF_FILE" ]; then
    PDF_EXISTS="true"
    MTIME=$(stat -c %Y "$PDF_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PDF_MODIFIED="true"
    fi
fi

# 3. Analyze Diagram Content (Using Python to parse XML)
# This script extracts text labels, colors, and shape counts
python3 - <<EOF
import sys
import xml.etree.ElementTree as ET
import urllib.parse
import base64
import zlib
import json
import re

diagram_path = "$DIAGRAM_FILE"
output_json = "/tmp/analysis_result.json"

result = {
    "total_shapes": 0,
    "version_labels": [],
    "feature_keywords": [],
    "fill_colors": [],
    "containers": 0,
    "eol_marker": False
}

def decode_mxfile(text):
    try:
        # draw.io often URL-encodes then base64 then deflates
        decoded = base64.b64decode(text)
        xml_str = zlib.decompress(decoded, -15).decode('utf-8')
        return xml_str
    except Exception:
        return text  # Might be plain XML

try:
    if "$DIAGRAM_EXISTS" == "true":
        tree = ET.parse(diagram_path)
        root = tree.getroot()
        
        # Handle compressed diagram data
        diagram_node = root.find("diagram")
        if diagram_node is not None and diagram_node.text:
            xml_content = decode_mxfile(diagram_node.text)
            # Re-parse the inner XML
            root = ET.fromstring(xml_content)
        
        # Find all cells
        cells = root.findall(".//mxCell")
        result["total_shapes"] = len(cells)
        
        text_content = []
        styles = []
        
        for cell in cells:
            val = cell.get("value", "")
            style = cell.get("style", "")
            
            # Collect text
            if val:
                # Remove HTML tags for cleaner checking
                clean_val = re.sub('<[^<]+?>', ' ', val).lower()
                text_content.append(clean_val)
                
                # Check for versions like "3.10", "3.11"
                versions = re.findall(r'3\.\d+', clean_val)
                result["version_labels"].extend(versions)
                
                # Check for EOL
                if "eol" in clean_val or "end of life" in clean_val:
                    result["eol_marker"] = True
            
            # Collect styles
            if style:
                styles.append(style)
                # Check for fill colors
                fills = re.findall(r'fillColor=(#[0-9a-fA-F]{6})', style)
                result["fill_colors"].extend(fills)
                
                # Check for container/group properties
                if "container=1" in style or "swimlane" in style or "group" in style:
                    result["containers"] += 1

        # Check for keywords in all text
        keywords = ["async", "await", "f-string", "walrus", "pattern matching", "match/case", "type hint", "dataclass", "pathlib"]
        found_keywords = [kw for kw in keywords if any(kw in t for t in text_content)]
        result["feature_keywords"] = list(set(found_keywords))
        
        # Deduplicate colors
        result["fill_colors"] = list(set(result["fill_colors"]))
        result["version_labels"] = list(set(result["version_labels"]))

except Exception as e:
    result["error"] = str(e)

with open(output_json, 'w') as f:
    json.dump(result, f)
EOF

# Merge bash checks and python analysis
# Create final result JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "diagram_exists": $DIAGRAM_EXISTS,
    "diagram_modified": $DIAGRAM_MODIFIED,
    "pdf_exists": $PDF_EXISTS,
    "pdf_modified": $PDF_MODIFIED,
    "initial_shape_count": $INITIAL_SHAPE_COUNT,
    "analysis": $(cat /tmp/analysis_result.json 2>/dev/null || echo "{}")
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json