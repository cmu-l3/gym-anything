#!/bin/bash
set -e

echo "=== Exporting WiFi Coverage Heatmap Results ==="

# 1. Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Files
DRAWIO_FILE="/home/ga/Diagrams/wifi_project.drawio"
EXPORT_FILE="/home/ga/Diagrams/exports/wifi_coverage_map.png"

# 3. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Python Script to Analyze the .drawio XML
# Draw.io files are usually Deflate-compressed XML inside Base64 inside URL-encoding.
# We need to extract the structure to verify layers and opacity.

cat << 'PY_EOF' > /tmp/analyze_drawio.py
import sys
import json
import os
import base64
import zlib
import urllib.parse
import xml.etree.ElementTree as ET

def decode_drawio(content):
    """Decode standard draw.io compressed format"""
    try:
        # It's usually URL encoded -> Base64 -> Deflate (raw, no header)
        # Check if it looks like XML directly first
        if content.strip().startswith('<mxfile'):
            try:
                # Might be uncompressed XML
                ET.fromstring(content)
                return content
            except:
                pass # Parse failed, try decoding
        
        # Parse XML to find diagram node
        tree = ET.ElementTree(ET.fromstring(content))
        root = tree.getroot()
        diagram = root.find('diagram')
        if diagram is None or not diagram.text:
            return content # Maybe uncompressed inside?
            
        b64_data = diagram.text
        # Decode Base64
        compressed = base64.b64decode(b64_data)
        # Decompress (raw deflate)
        xml_data = zlib.decompress(compressed, -15)
        return urllib.parse.unquote(xml_data.decode('utf-8'))
    except Exception as e:
        return f"ERROR: {str(e)}"

def analyze(file_path):
    result = {
        "exists": False,
        "layers": [],
        "layer_count": 0,
        "floor_plan_locked": False,
        "has_image": False,
        "ap_count": 0,
        "coverage_shapes": 0,
        "transparent_shapes": 0,
        "error": None
    }
    
    if not os.path.exists(file_path):
        return result
    
    result["exists"] = True
    
    try:
        with open(file_path, 'r') as f:
            raw_content = f.read()
            
        xml_content = decode_drawio(raw_content)
        
        # Handle cases where decoding returns error string
        if xml_content.startswith("ERROR"):
            # Fallback: try parsing raw content as uncompressed xml
            xml_content = raw_content

        # Decode URL encoding if present (common in inner XML)
        xml_content = urllib.parse.unquote(xml_content)
        
        root = ET.fromstring(xml_content)
        
        # Find mxGraphModel/root
        # Structure is usually <mxGraphModel><root><mxCell id="0"/><mxCell id="1" parent="0"/> ...
        # Layers are children of root with parent="0"
        
        graph_model = root.find('.//mxGraphModel')
        if graph_model is None:
            # Maybe direct root children?
            model_root = root
        else:
            model_root = graph_model.find('root')
            
        if model_root is None:
            result["error"] = "No root found in XML"
            return result

        # 1. Analyze Layers (children of root where parent="0")
        # Note: id="0" is the root node, id="1" is usually the default layer.
        # Additional layers are siblings of id="1".
        
        for cell in model_root.findall('mxCell'):
            parent = cell.get('parent')
            cid = cell.get('id')
            value = cell.get('value', '')
            style = cell.get('style', '')
            
            # Identify Layers
            # Layers usually have parent="0" (except the root node itself which has no parent)
            if parent == "0":
                layer_name = value if value else "Untitled Layer"
                is_locked = cell.get('locked') == '1'
                
                result["layers"].append({
                    "id": cid,
                    "name": layer_name,
                    "locked": is_locked
                })
                
                if "floor" in layer_name.lower() and is_locked:
                    result["floor_plan_locked"] = True
        
        result["layer_count"] = len(result["layers"])

        # 2. Analyze Content
        # We need to find which layer items belong to.
        # Items have parent="layer_id"
        
        for cell in model_root.findall('mxCell'):
            style = cell.get('style', '').lower()
            value = cell.get('value', '').lower()
            parent_id = cell.get('parent')
            
            # Detect Image (Floor Plan)
            # Usually has style containing "image;" or "shape=image"
            if "image" in style and parent_id:
                # Check if it's on a floor plan layer
                for layer in result["layers"]:
                    if layer["id"] == parent_id and "floor" in layer["name"].lower():
                        result["has_image"] = True
            
            # Detect APs
            # Standard AP shape often called "wireless_access_point" or has label "access point"
            if ("wireless" in style and "access" in style) or \
               ("access point" in value) or \
               ("mxgraph.cisco.wireless.access_point" in style):
                result["ap_count"] += 1
                
            # Detect Coverage Circles
            # Ellipse shape
            if "ellipse" in style:
                result["coverage_shapes"] += 1
                
                # Check Transparency
                # Style attributes: "opacity=50;" or "fillColor=#RRGGBB" (sometimes alpha is separate)
                # Or "fillColor=none" is transparent but not a heatmap.
                # We look for "opacity" key or "fillColor" with alpha? 
                # Draw.io usually puts opacity=X in style string.
                
                is_transparent = False
                if "opacity" in style:
                    # Parse opacity value
                    parts = style.split(';')
                    for part in parts:
                        if part.startswith("opacity="):
                            try:
                                op_val = int(part.split('=')[1])
                                if op_val < 100:
                                    is_transparent = True
                            except:
                                pass
                
                # Also check for "alpha" in color (less common in simple style string)
                if is_transparent:
                    result["transparent_shapes"] += 1

    except Exception as e:
        result["error"] = str(e)
        import traceback
        traceback.print_exc()

    print(json.dumps(result))

if __name__ == "__main__":
    analyze(sys.argv[1])
PY_EOF

# 5. Run analysis
echo "Analyzing .drawio structure..."
ANALYSIS_JSON=$(python3 /tmp/analyze_drawio.py "$DRAWIO_FILE")
echo "Analysis result: $ANALYSIS_JSON"

# 6. Check Export File
EXPORT_EXISTS="false"
if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_FILE")
else
    EXPORT_SIZE=0
fi

# 7. Create Result JSON
cat << JSON_EOF > /tmp/task_result.json
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "drawio_file_exists": $([ -f "$DRAWIO_FILE" ] && echo "true" || echo "false"),
    "export_file_exists": $EXPORT_EXISTS,
    "export_file_size": $EXPORT_SIZE,
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
JSON_EOF

# Move to final location (ensure permissions)
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json