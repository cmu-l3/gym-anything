#!/bin/bash
echo "=== Exporting GDPR Data Lineage Result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define paths
DIAGRAM_PATH="/home/ga/Diagrams/gdpr_data_lineage.drawio"
PDF_PATH="/home/ga/Diagrams/gdpr_data_lineage.pdf"
RESULT_JSON="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Python script to analyze the drawio file
# This handles XML parsing and decompressing draw.io's Deflate+Base64 content
cat << 'EOF' > /tmp/analyze_drawio.py
import sys
import os
import json
import base64
import zlib
import urllib.parse
from xml.etree import ElementTree

diagram_path = sys.argv[1]
pdf_path = sys.argv[2]
task_start = int(sys.argv[3])

result = {
    "file_exists": False,
    "file_modified": False,
    "pdf_exists": False,
    "pdf_size": 0,
    "page_count": 0,
    "page_names": [],
    "shape_count": 0,
    "edge_count": 0,
    "text_content": [],
    "gdpr_annotations_found": 0,
    "system_names_found": [],
    "cross_border_page": False,
    "color_coding_used": False
}

if os.path.exists(diagram_path):
    result["file_exists"] = True
    mtime = os.path.getmtime(diagram_path)
    if mtime > task_start:
        result["file_modified"] = True
    
    try:
        tree = ElementTree.parse(diagram_path)
        root = tree.getroot()
        
        # Draw.io files can be uncompressed XML or compressed inside <diagram> tags
        diagrams = root.findall("diagram")
        result["page_count"] = len(diagrams)
        
        all_xml_content = ""
        
        for d in diagrams:
            name = d.get("name", "")
            result["page_names"].append(name)
            if "cross" in name.lower() or "border" in name.lower() or "transfer" in name.lower():
                result["cross_border_page"] = True
                
            # Content might be text (compressed) or direct child nodes
            if d.text and d.text.strip():
                try:
                    # Standard draw.io compression: Base64 -> Inflate (raw) -> URLDecode (sometimes)
                    # Usually just Base64 -> Inflate
                    data = base64.b64decode(d.text)
                    try:
                        xml_str = zlib.decompress(data, -15).decode('utf-8')
                    except:
                        # Fallback for standard zlib
                        xml_str = zlib.decompress(data).decode('utf-8')
                        
                    xml_str = urllib.parse.unquote(xml_str)
                    all_xml_content += xml_str
                except Exception as e:
                    # Could be uncompressed text?
                    all_xml_content += d.text
            else:
                # Iterate children directly if uncompressed
                for child in d:
                    all_xml_content += ElementTree.tostring(child, encoding='unicode')

        # Now parse the aggregated XML content to find cells
        # We wrap it in a dummy root to parse valid XML
        wrapped_xml = f"<root>{all_xml_content}</root>"
        try:
            content_root = ElementTree.fromstring(wrapped_xml)
            cells = content_root.findall(".//mxCell")
            
            shapes = 0
            edges = 0
            distinct_colors = set()
            
            for cell in cells:
                is_vertex = cell.get("vertex") == "1"
                is_edge = cell.get("edge") == "1"
                value = cell.get("value", "")
                style = cell.get("style", "")
                
                if is_vertex:
                    shapes += 1
                    # Check for color in style
                    if "fillColor" in style:
                        # Extract color code roughly
                        parts = style.split(";")
                        for p in parts:
                            if p.startswith("fillColor="):
                                distinct_colors.add(p.split("=")[1])
                                
                if is_edge:
                    edges += 1
                
                if value:
                    # Clean HTML tags from value if present
                    clean_value = ''.join(ElementTree.fromstring(f"<div>{value}</div>").itertext()) if "<" in value else value
                    result["text_content"].append(clean_value)

            result["shape_count"] = shapes
            result["edge_count"] = edges
            if len(distinct_colors) >= 3:
                result["color_coding_used"] = True

        except Exception as e:
            # Fallback simple string search if XML parsing fails
            result["error"] = str(e)

    except Exception as e:
        result["error"] = str(e)

if os.path.exists(pdf_path):
    result["pdf_exists"] = True
    result["pdf_size"] = os.path.getsize(pdf_path)

print(json.dumps(result))
EOF

# 4. Run Python script
python3 /tmp/analyze_drawio.py "$DIAGRAM_PATH" "$PDF_PATH" "$TASK_START" > "$RESULT_JSON"

# 5. Clean up temp script
rm /tmp/analyze_drawio.py

# 6. Check if app was running (for bonus checks)
if pgrep -f "drawio" > /dev/null; then
    # Use jq to add app_running=true
    jq '. + {"app_running": true}' "$RESULT_JSON" > "${RESULT_JSON}.tmp" && mv "${RESULT_JSON}.tmp" "$RESULT_JSON"
else
    jq '. + {"app_running": false}' "$RESULT_JSON" > "${RESULT_JSON}.tmp" && mv "${RESULT_JSON}.tmp" "$RESULT_JSON"
fi

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="