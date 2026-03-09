#!/bin/bash
set -e

echo "=== Exporting ER Diagram Results ==="

# Define paths
DRAWIO_FILE="/home/ga/Diagrams/chinook_er_diagram.drawio"
PNG_FILE="/home/ga/Diagrams/exports/chinook_er_diagram.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize result variables
FILE_EXISTS="false"
PNG_EXISTS="false"
FILE_MODIFIED="false"
XML_VALID="false"
ENTITY_COUNT=0
RELATIONSHIP_COUNT=0
ATTRIBUTE_COUNT=0
FOUND_ENTITIES="[]"
HAS_PK="false"
HAS_FK="false"

# Check file existence
if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
fi

# Parse XML content if file exists
if [ "$FILE_EXISTS" = "true" ]; then
    # Use python to parse the drawio XML (which might be compressed)
    # This script extracts text to find entity names and counts shapes
    python3 << PYEOF > /tmp/xml_analysis.json
import sys
import xml.etree.ElementTree as ET
import base64
import zlib
import urllib.parse
import json
import re

file_path = "$DRAWIO_FILE"
result = {
    "valid_xml": False,
    "entity_count": 0,
    "relationship_count": 0,
    "attribute_count": 0,
    "found_entities": [],
    "has_pk": False,
    "has_fk": False,
    "raw_text": ""
}

try:
    tree = ET.parse(file_path)
    root = tree.getroot()
    
    # Handle draw.io compressed format
    xml_content = ""
    if root.tag == 'mxfile':
        for diagram in root.findall('diagram'):
            if diagram.text:
                try:
                    # Decode: Base64 -> Inflate -> URLDecode
                    data = base64.b64decode(diagram.text)
                    xml_content += zlib.decompress(data, -15).decode('utf-8')
                except:
                    # Fallback for uncompressed or different format
                    xml_content += diagram.text
    else:
        # Just raw XML
        xml_content = ET.tostring(root, encoding='unicode')

    result['valid_xml'] = True
    
    # Analyze text content
    # Normalize text
    text_content = xml_content.lower()
    result['raw_text'] = text_content[:5000] # Snippet for debugging

    # Check for specific entities (Exact table names)
    target_entities = ["Artist", "Album", "Track", "Genre", "MediaType", "Playlist", "PlaylistTrack"]
    found = []
    for entity in target_entities:
        # Check case-insensitive but usually users type exact names
        if entity.lower() in text_content:
            found.append(entity)
    result['found_entities'] = found

    # Count Shapes (vertices) and Edges
    # Simple regex counting is safer than trying to parse the inner compressed XML structurally if it's complex
    # vertex="1" indicates a shape
    result['entity_count'] = len(re.findall(r'vertex="1"', xml_content))
    
    # edge="1" indicates a connector
    result['relationship_count'] = len(re.findall(r'edge="1"', xml_content))

    # Attributes often appear as simple text or within object values
    # We estimate attribute count by checking total text items minus entities
    # This is a rough heuristic
    result['attribute_count'] = len(re.findall(r'value="[^"]+"', xml_content))

    # Check for PK/FK indicators
    if "pk" in text_content or "primary" in text_content or "key" in text_content:
        result['has_pk'] = True
    if "fk" in text_content or "foreign" in text_content:
        result['has_fk'] = True

except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
PYEOF

    # Load Python analysis results into bash variables
    if [ -f /tmp/xml_analysis.json ]; then
        XML_VALID=$(jq -r .valid_xml /tmp/xml_analysis.json)
        ENTITY_COUNT=$(jq -r .entity_count /tmp/xml_analysis.json)
        RELATIONSHIP_COUNT=$(jq -r .relationship_count /tmp/xml_analysis.json)
        ATTRIBUTE_COUNT=$(jq -r .attribute_count /tmp/xml_analysis.json)
        FOUND_ENTITIES=$(jq -r .found_entities /tmp/xml_analysis.json)
        HAS_PK=$(jq -r .has_pk /tmp/xml_analysis.json)
        HAS_FK=$(jq -r .has_fk /tmp/xml_analysis.json)
    fi
fi

# Create final JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "png_exists": $PNG_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "xml_valid": $XML_VALID,
    "entity_shape_count": $ENTITY_COUNT,
    "relationship_count": $RELATIONSHIP_COUNT,
    "found_entities": $FOUND_ENTITIES,
    "has_pk": $HAS_PK,
    "has_fk": $HAS_FK,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Export complete. Result:"
cat /tmp/task_result.json