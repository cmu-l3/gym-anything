#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Update Weekly Ops Deck Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/Presentations/Ops_Review_Week_43.odp"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if target file exists
FILE_EXISTS="false"
FILE_MTIME="0"
FILE_SIZE="0"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
fi

# Parse the ODP file to extract content for verification
# We run this python script inside the container to avoid dependency issues on host
echo "Parsing ODP file content..."

python3 << PYEOF > /tmp/parsed_content.json
import json
import sys
import os

try:
    from odf.opendocument import load
    from odf.text import P
    from odf.table import Table, TableRow, TableCell
    from odf.draw import CustomShape
    from odf.style import Style, GraphicProperties
    
    filepath = "$TARGET_FILE"
    
    if not os.path.exists(filepath):
        print(json.dumps({"error": "File not found"}))
        sys.exit(0)
        
    doc = load(filepath)
    
    result = {
        "slides": [],
        "shapes": [],
        "tables": []
    }
    
    # Simple extraction strategy
    # 1. Get all text per slide
    # 2. Get specific table content
    # 3. Get shape colors
    
    # We iterate through the XML structure manually to maintain slide order approximately
    # Note: odfpy access is a bit flat, but we can try to group by draw:page
    
    for slide_idx, slide in enumerate(doc.presentation.getElementsByType(type=None)): # Iterate children if possible
        # Getting pages directly
        pass

    # Better approach with odfpy: get all Pages
    from odf.draw import Page
    pages = doc.getElementsByType(Page)
    
    for i, page in enumerate(pages):
        slide_text = []
        
        # Extract Text
        for p in page.getElementsByType(P):
            if p.firstChild:
                # Basic text extraction
                text = ""
                for child in p.childNodes:
                    if child.nodeType == 3: # Text node
                        text += str(child.data)
                if text.strip():
                    slide_text.append(text.strip())
        
        result["slides"].append({
            "index": i,
            "text": slide_text
        })
        
        # Extract Shapes (specifically look for MigrationStatus)
        for shape in page.getElementsByType(CustomShape):
            name = shape.getAttribute('name')
            style_name = shape.getAttribute('stylename')
            
            # Find the style definition
            fill_color = "unknown"
            if style_name:
                # Search in automatic styles
                for style in doc.automaticstyles.childNodes:
                    if style.getAttribute('name') == style_name:
                        for prop in style.getElementsByType(GraphicProperties):
                            fill_color = prop.getAttribute('fillcolor')
            
            result["shapes"].append({
                "slide": i,
                "name": name,
                "fill_color": fill_color
            })

    # Extract Table Data
    for table in doc.getElementsByType(Table):
        table_data = []
        for row in table.getElementsByType(TableRow):
            row_data = []
            for cell in row.getElementsByType(TableCell):
                cell_text = ""
                for p in cell.getElementsByType(P):
                    for child in p.childNodes:
                        if child.nodeType == 3:
                            cell_text += str(child.data)
                row_data.append(cell_text.strip())
            table_data.append(row_data)
        result["tables"].append(table_data)

    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

# Combine everything into final result
# We read the parsed content we just generated
PARSED_CONTENT=$(cat /tmp/parsed_content.json)
EXPECTED_VALUES=$(cat /tmp/expected_values.json 2>/dev/null || echo "{}")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_mtime": $FILE_MTIME,
    "file_size": $FILE_SIZE,
    "parsed_content": $PARSED_CONTENT,
    "expected_values": $EXPECTED_VALUES,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="