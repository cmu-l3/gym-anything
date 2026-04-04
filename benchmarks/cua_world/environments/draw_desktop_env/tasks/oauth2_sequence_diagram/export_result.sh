#!/bin/bash
# Do NOT use set -e

echo "=== Exporting oauth2_sequence_diagram result ==="

# Final screenshot
DISPLAY=:1 import -window root /tmp/oauth_task_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/oauth2_sequence.drawio"
PNG_FILE="/home/ga/Desktop/oauth2_sequence.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check File Existence & Timestamps
FILE_EXISTS="false"
FILE_MODIFIED_AFTER_START="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
fi

# 2. Check PNG Export
PNG_EXISTS="false"
PNG_SIZE=0
PNG_VALID="false"

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
    if file "$PNG_FILE" 2>/dev/null | grep -qi "png"; then
        PNG_VALID="true"
    fi
fi

# 3. Analyze Diagram Content (XML Parsing)
# This Python script handles compressed draw.io XML and extracts key metrics
python3 << 'PYEOF' > /tmp/oauth_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET
from urllib.parse import unquote

filepath = "/home/ga/Desktop/oauth2_sequence.drawio"
result = {
    "num_pages": 0,
    "page_names": [],
    "participants_found": [],
    "messages_count": 0,
    "self_messages_count": 0,
    "keywords_found": [],
    "has_note": False,
    "error": None
}

REQUIRED_PARTICIPANTS = ["user", "client", "authorization server", "resource server"]
KEYWORDS = ["code_challenge", "code_verifier", "access_token", "refresh_token", 
            "bearer", "authorization code", "pkce", "redirect"]

def decompress_diagram(content):
    if not content or not content.strip():
        return None
    try:
        # Try raw inflate
        decoded = base64.b64decode(content.strip())
        return ET.fromstring(zlib.decompress(decoded, -15))
    except Exception:
        pass
    try:
        # Try URL decoded
        decoded_str = unquote(content.strip())
        if decoded_str.strip().startswith('<'):
            return ET.fromstring(decoded_str)
    except Exception:
        pass
    return None

try:
    if not os.path.exists(filepath):
        result["error"] = "File not found"
    else:
        tree = ET.parse(filepath)
        root = tree.getroot()

        # Pages
        diagrams = root.findall('diagram')
        result["num_pages"] = len(diagrams)
        for d in diagrams:
            if d.get('name'):
                result["page_names"].append(d.get('name').lower())

        # Collect all cells from all pages
        all_cells = []
        for d in diagrams:
            content = d.text
            if content:
                page_root = decompress_diagram(content)
                if page_root is not None:
                    all_cells.extend(list(page_root.iter('mxCell')))
        
        # Also check direct model (uncompressed save)
        for cell in root.iter('mxCell'):
            if cell not in all_cells:
                all_cells.append(cell)

        all_text = []

        # Analyze cells
        for cell in all_cells:
            val = str(cell.get('value') or '').lower()
            style = str(cell.get('style') or '').lower()
            
            # Remove HTML tags for text analysis
            clean_val = re.sub(r'<[^>]+>', ' ', val)
            if clean_val.strip():
                all_text.append(clean_val)

            # Check for Note/Comment shapes
            if 'note' in style or 'comment' in style or 'callout' in style:
                if len(clean_val) > 5: # Valid note usually has text
                    result["has_note"] = True

            # Check Edges (Messages)
            if cell.get('edge') == '1':
                source = cell.get('source')
                target = cell.get('target')
                
                # Check for labeled edges
                if clean_val.strip():
                    result["messages_count"] += 1
                
                # Check Self-Message
                if source and target and source == target:
                    result["self_messages_count"] += 1

        # Analyze extracted text for Keywords and Participants
        full_text_blob = " ".join(all_text)
        
        for p in REQUIRED_PARTICIPANTS:
            # Check if participant name exists in text (likely a Lifeline label)
            if p in full_text_blob:
                result["participants_found"].append(p)
        
        for k in KEYWORDS:
            if k in full_text_blob or k.replace('_', ' ') in full_text_blob:
                result["keywords_found"].append(k)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "png_valid": $PNG_VALID,
    "analysis": $(cat /tmp/oauth_analysis.json)
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json