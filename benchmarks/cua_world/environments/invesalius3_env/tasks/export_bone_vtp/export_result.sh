#!/bin/bash
set -e

echo "=== Exporting export_bone_vtp result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/cranial_bone.vtp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture final state visual evidence
take_screenshot /tmp/task_final.png

# 2. Analyze the output file using Python
# We use Python because VTP is XML-based and we need to verify structure robustly
python3 << PYEOF
import os
import json
import xml.etree.ElementTree as ET
import re

result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "file_created_during_task": False,
    "is_valid_xml": False,
    "is_vtp_format": False,
    "has_polydata": False,
    "point_count": 0,
    "poly_count": 0,
    "error": None
}

filepath = "$OUTPUT_FILE"
task_start = $TASK_START
task_end = $TASK_END

if os.path.exists(filepath):
    result["file_exists"] = True
    stat = os.stat(filepath)
    result["file_size_bytes"] = stat.st_size
    
    # Check timestamp
    # Allow small buffer for filesystem sync issues
    if stat.st_mtime >= (task_start - 1):
        result["file_created_during_task"] = True
    
    # Verify Content
    try:
        # VTP files can be huge, but the XML headers are at the top.
        # However, ElementTree needs a valid file. 
        # Since VTP can have appended binary data, standard XML parsers might fail 
        # if not handled correctly, but VTK XML parsers usually handle the AppendedData tag.
        # We will attempt to parse the header structure.
        
        # Read first 2KB to check header if file is large/binary
        with open(filepath, 'rb') as f:
            head = f.read(2048).decode('utf-8', errors='ignore')
            
        if "<VTKFile" in head and 'type="PolyData"' in head:
            result["is_vtp_format"] = True
            
        # Try full parse for structure if size allows (limit < 500MB for parsing in this env)
        if result["file_size_bytes"] < 500 * 1024 * 1024:
            try:
                # We can try to parse. Note: VTK XML often puts binary data in AppendedData
                # which might choke some simple XML parsers if not valid chars, 
                # but InVesalius usually exports valid XML structure.
                tree = ET.parse(filepath)
                root = tree.getroot()
                
                if root.tag == "VTKFile" and root.attrib.get("type") == "PolyData":
                    result["is_valid_xml"] = True
                    result["is_vtp_format"] = True
                    result["has_polydata"] = True
                    
                    # Find Piece to get counts
                    # XPath: PolyData/Piece
                    polydata = root.find("PolyData")
                    if polydata is not None:
                        piece = polydata.find("Piece")
                        if piece is not None:
                            result["point_count"] = int(piece.attrib.get("NumberOfPoints", 0))
                            result["poly_count"] = int(piece.attrib.get("NumberOfPolys", 0))
                            # Sometimes strips are used instead of polys
                            if result["poly_count"] == 0:
                                result["poly_count"] = int(piece.attrib.get("NumberOfStrips", 0))

            except ET.ParseError:
                # Fallback for Appended Binary data which might confuse ET
                pass

        # Regex fallback if XML parsing failed (common with binary appended data)
        if result["point_count"] == 0:
            with open(filepath, 'r', errors='ignore') as f:
                content = f.read(4096) # Read header area
                
                p_match = re.search(r'NumberOfPoints="(\d+)"', content)
                if p_match:
                    result["point_count"] = int(p_match.group(1))
                    
                poly_match = re.search(r'NumberOfPolys="(\d+)"', content)
                if poly_match:
                    result["poly_count"] = int(poly_match.group(1))
                else:
                    strip_match = re.search(r'NumberOfStrips="(\d+)"', content)
                    if strip_match:
                        result["poly_count"] = int(strip_match.group(1))

    except Exception as e:
        result["error"] = str(e)

# 3. Save Result JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="