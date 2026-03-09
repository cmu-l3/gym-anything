#!/bin/bash
echo "=== Exporting Fishbone RCA Result ==="

# Define paths
DIAGRAM_FILE="/home/ga/Diagrams/medication_rca.drawio"
PDF_FILE="/home/ga/Diagrams/exports/medication_rca.pdf"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
INITIAL_SHAPE_COUNT=$(cat /tmp/initial_shape_count 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existence
FILE_EXISTS="false"
PDF_EXISTS="false"
FILE_MODIFIED="false"
PDF_CREATED="false"

if [ -f "$DIAGRAM_FILE" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$DIAGRAM_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
    # Check if PDF is non-empty
    PDF_SIZE=$(stat -c %s "$PDF_FILE")
    if [ "$PDF_SIZE" -gt 1000 ]; then
        MTIME=$(stat -c %Y "$PDF_FILE")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            PDF_CREATED="true"
        fi
    fi
fi

# Analyze diagram content using Python
# We run this here to parse the XML structure and extract metrics
# This handles both plain XML and the compressed mxfile format
python3 << PY_EOF > /tmp/diagram_analysis.json
import sys
import xml.etree.ElementTree as ET
import base64
import zlib
import urllib.parse
import json
import re

file_path = "$DIAGRAM_FILE"
analysis = {
    "vertex_count": 0,
    "edge_count": 0,
    "text_content": [],
    "fill_colors": [],
    "title_found": False,
    "error": None
}

try:
    tree = ET.parse(file_path)
    root = tree.getroot()

    xml_content = None

    # Check if this is a compressed draw.io file
    if root.tag == 'mxfile':
        diagrams = root.findall('diagram')
        if diagrams:
            # Look for the first diagram
            d = diagrams[0]
            if d.text:
                try:
                    # Decode compressed content
                    # Standard draw.io compression: URL encoded -> Base64 -> Deflate (no header)
                    data = base64.b64decode(d.text)
                    xml_content = zlib.decompress(data, -15).decode('utf-8')
                except Exception as e:
                    # Might be uncompressed if user saved it that way
                    xml_content = d.text
    
    # If not compressed or failed to decompress, try parsing file directly if it's already graph model
    if not xml_content and root.tag == 'mxGraphModel':
        xml_content = ET.tostring(root, encoding='unicode')
    
    # Parse the inner graph model
    if xml_content:
        # Wrap in fake root if needed for valid XML parsing
        if not xml_content.strip().startswith('<'):
             # If decoding failed, it might be raw text
             pass
        else:
            try:
                graph_root = ET.fromstring(xml_content)
                
                # Analyze cells
                for cell in graph_root.iter('mxCell'):
                    # Count vertices (shapes)
                    if cell.get('vertex') == '1':
                        analysis['vertex_count'] += 1
                        
                        # Extract text
                        val = cell.get('value', '')
                        if val:
                            # Remove HTML tags if present
                            clean_text = re.sub('<[^<]+?>', ' ', val)
                            analysis['text_content'].append(clean_text.strip())
                            
                            if "RCA-2024-0847" in clean_text:
                                analysis['title_found'] = True
                        
                        # Extract color
                        style = cell.get('style', '')
                        fill_match = re.search(r'fillColor=([^;]+)', style)
                        if fill_match:
                            color = fill_match.group(1)
                            if color not in ['none', '#ffffff', 'white']:
                                if color not in analysis['fill_colors']:
                                    analysis['fill_colors'].append(color)

                    # Count edges (connections)
                    if cell.get('edge') == '1':
                        analysis['edge_count'] += 1

            except Exception as e:
                analysis['error'] = f"Inner XML Parse Error: {str(e)}"
    else:
        # Fallback for uncompressed simple XML
        for cell in root.iter('mxCell'):
            if cell.get('vertex') == '1':
                analysis['vertex_count'] += 1
                val = cell.get('value', '')
                if val:
                    clean_text = re.sub('<[^<]+?>', ' ', val)
                    analysis['text_content'].append(clean_text.strip())
                    if "RCA-2024-0847" in clean_text:
                        analysis['title_found'] = True
                
                style = cell.get('style', '')
                fill_match = re.search(r'fillColor=([^;]+)', style)
                if fill_match:
                    color = fill_match.group(1)
                    if color not in analysis['fill_colors']:
                        analysis['fill_colors'].append(color)
            if cell.get('edge') == '1':
                analysis['edge_count'] += 1

except Exception as e:
    analysis['error'] = f"File Parse Error: {str(e)}"

print(json.dumps(analysis))
PY_EOF

# Read analysis
ANALYSIS=$(cat /tmp/diagram_analysis.json)

# Create final JSON result
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "pdf_exists": $PDF_EXISTS,
    "pdf_created_during_task": $PDF_CREATED,
    "initial_shape_count": $INITIAL_SHAPE_COUNT,
    "diagram_analysis": $ANALYSIS
}
EOF

echo "Result exported to /tmp/task_result.json"