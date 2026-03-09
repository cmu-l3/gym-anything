#!/bin/bash
echo "=== Exporting wordpress_c4_architecture result ==="

# Record task end info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_FILE="/home/ga/Desktop/wordpress_c4.drawio"
PNG_FILE="/home/ga/Desktop/wordpress_c4.png"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check file status
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

# Parse the draw.io XML to verify content
# We use Python to handle XML parsing, including base64/deflate decoding if needed
python3 << 'PYEOF' > /tmp/c4_analysis.json
import json, sys, os, base64, zlib, re
import xml.etree.ElementTree as ET

result = {
    "pages": 0,
    "shapes": [],
    "edges": 0,
    "c4_keywords": 0,
    "context_matches": 0,
    "container_matches": 0,
    "has_boundary": False,
    "edge_labels": 0
}

filepath = "/home/ga/Desktop/wordpress_c4.drawio"

def decode_diagram(text):
    if not text: return None
    try:
        # Try raw XML first
        if text.strip().startswith('<'):
            return ET.fromstring(text)
        # Try base64 + inflate
        decoded = base64.b64decode(text)
        inflated = zlib.decompress(decoded, -15)
        return ET.fromstring(inflated)
    except:
        return None

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Count pages
        diagrams = root.findall('diagram')
        result["pages"] = len(diagrams)
        
        all_text = []
        
        # Iterate over all pages
        for diagram in diagrams:
            mxGraphModel = decode_diagram(diagram.text)
            if mxGraphModel is None:
                # Try getting children if uncompressed
                mxGraphModel = diagram.find('mxGraphModel')
            
            if mxGraphModel is not None:
                root_cell = mxGraphModel.find('root')
                if root_cell is not None:
                    for cell in root_cell:
                        val = cell.get('value', '')
                        style = cell.get('style', '')
                        
                        # Clean HTML from value
                        clean_val = re.sub(r'<[^>]+>', ' ', val).strip()
                        if clean_val:
                            all_text.append(clean_val)
                            
                        # Check vertex (shapes)
                        if cell.get('vertex') == '1':
                            result["shapes"].append(clean_val)
                            
                            # Check for System Boundary (often Group or Swimlane with "WordPress" in name)
                            if 'WordPress' in clean_val and ('swimlane' in style or 'group' in style or 'container' in style):
                                result["has_boundary"] = True
                            
                            # Check for C4 shape usage via style
                            if 'c4' in style.lower() or 'person' in style.lower() or 'software system' in style.lower():
                                result["c4_keywords"] += 1
                                
                        # Check edges
                        if cell.get('edge') == '1':
                            result["edges"] += 1
                            if clean_val:
                                result["edge_labels"] += 1

        # Analyze keywords in text
        context_keywords = ["Reader", "Author", "Admin", "Email", "CDN", "Social", "Plugin", "Repository", "wordpress.org"]
        container_keywords = ["Apache", "Nginx", "PHP", "wp-includes", "Database", "MySQL", "wp-content", "uploads", "Cron", "WP-Admin", "wp-json"]
        
        full_text_blob = " ".join(all_text).lower()
        
        for kw in context_keywords:
            if kw.lower() in full_text_blob:
                result["context_matches"] += 1
                
        for kw in container_keywords:
            if kw.lower() in full_text_blob:
                result["container_matches"] += 1

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Copy parsing result to final task result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/c4_analysis.json)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"