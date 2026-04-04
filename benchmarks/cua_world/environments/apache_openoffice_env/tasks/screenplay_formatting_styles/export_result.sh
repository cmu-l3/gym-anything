#!/bin/bash
echo "=== Exporting Screenplay Formatting Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/Nebula_Frontier_Sc3.odt"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# 2. Check file existence and timestamps
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Python script to parse ODT structure deeply
# We extract paragraphs, their styles, and the style definitions (indents)
python3 << 'PYEOF'
import zipfile
import json
import re
import os
import sys
import xml.etree.ElementTree as ET

output_path = "/home/ga/Documents/Nebula_Frontier_Sc3.odt"
result_data = {
    "paragraphs": [],
    "style_definitions": {},
    "error": None
}

if not os.path.exists(output_path):
    with open("/tmp/odt_analysis.json", "w") as f:
        json.dump(result_data, f)
    sys.exit(0)

try:
    with zipfile.ZipFile(output_path, 'r') as zf:
        # 1. Parse content.xml for text and style usage
        content_xml = zf.read('content.xml')
        root = ET.fromstring(content_xml)
        
        # Namespaces in ODT
        ns = {
            'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
            'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
            'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'
        }
        
        # Extract paragraphs
        for p in root.findall('.//text:p', ns):
            style_name = p.get(f"{{{ns['text']}}}style-name")
            # Get text content (recursively for spans)
            text_content = "".join(p.itertext()).strip()
            if text_content:
                result_data["paragraphs"].append({
                    "text": text_content,
                    "style": style_name
                })

        # 2. Parse styles.xml (and content.xml automatic styles) for indent definitions
        # We need to look in both places. Common styles are in styles.xml, auto styles in content.xml
        
        def extract_styles(xml_root, source_name):
            # Look for normal styles
            for style_node in xml_root.findall('.//style:style', ns):
                name = style_node.get(f"{{{ns['style']}}}name")
                family = style_node.get(f"{{{ns['style']}}}family")
                parent = style_node.get(f"{{{ns['style']}}}parent-style-name")
                
                if family == 'paragraph':
                    props = style_node.find('style:paragraph-properties', ns)
                    left_margin = "0"
                    right_margin = "0"
                    text_indent = "0"
                    
                    if props is not None:
                        left_margin = props.get(f"{{{ns['fo']}}}margin-left", "0")
                        right_margin = props.get(f"{{{ns['fo']}}}margin-right", "0")
                        text_indent = props.get(f"{{{ns['fo']}}}text-indent", "0")
                    
                    result_data["style_definitions"][name] = {
                        "source": source_name,
                        "parent": parent,
                        "margin_left": left_margin,
                        "margin_right": right_margin,
                        "text_indent": text_indent
                    }

        # Extract from content.xml (automatic styles)
        extract_styles(root, "content.xml")
        
        # Extract from styles.xml (common styles)
        if 'styles.xml' in zf.namelist():
            styles_xml = zf.read('styles.xml')
            styles_root = ET.fromstring(styles_xml)
            extract_styles(styles_root, "styles.xml")

except Exception as e:
    result_data["error"] = str(e)

with open("/tmp/odt_analysis.json", "w") as f:
    json.dump(result_data, f, indent=2)
PYEOF

# 4. Merge into final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "odt_analysis": $(cat /tmp/odt_analysis.json || echo "{}"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="