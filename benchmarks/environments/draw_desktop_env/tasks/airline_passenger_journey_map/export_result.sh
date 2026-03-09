#!/bin/bash
# Do NOT use set -e

echo "=== Exporting airline_passenger_journey_map result ==="

# Capture final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/passenger_journey_map.drawio"
PNG_FILE="/home/ga/Desktop/passenger_journey_map.png"
REQ_FILE="/home/ga/Desktop/passenger_journey_requirements.txt"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0
PNG_EXISTS="false"
PNG_SIZE=0
PNG_WIDTH=0

# Check .drawio file
if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    echo "Found drawio file: $FILE_SIZE bytes"
fi

# Check .png file
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
    
    # Get dimensions if possible
    if command -v identify &>/dev/null; then
        PNG_WIDTH=$(identify -format "%w" "$PNG_FILE" 2>/dev/null || echo "0")
    fi
    echo "Found png file: $PNG_SIZE bytes (width: $PNG_WIDTH)"
fi

# Deep XML Analysis using Python
# This handles compressed XML (deflate) which draw.io often uses
python3 << 'PYEOF' > /tmp/journey_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/passenger_journey_map.drawio"
result = {
    "num_pages": 0,
    "total_shapes": 0,
    "total_edges": 0,
    "swimlanes_found": 0,
    "text_content": "",
    "phases_found": [],
    "lanes_found": [],
    "content_keywords_found": [],
    "page2_keywords_found": [],
    "error": None
}

PHASES = ["research", "booking", "pre-departure", "airport", "in-flight", "arrival", "post-trip"]
LANES = ["touchpoint", "channel", "action", "emotion", "pain point", "opportunit"]
CONTENT_KEYWORDS = ["hidden fees", "bag drop", "security", "long queue", "lost luggage", 
                   "biometric", "bag tracking", "loyalty", "app", "upsell", "gate agent", "legroom"]
PAGE2_KEYWORDS = ["moments of truth", "booking confirmation", "boarding experience", "baggage claim"]

def decompress_diagram(content):
    if not content: return None
    try:
        # Try raw deflate (standard for draw.io compressed)
        decoded = base64.b64decode(content)
        return zlib.decompress(decoded, -15).decode('utf-8')
    except:
        try:
            # Try URL decoded
            from urllib.parse import unquote
            return unquote(content)
        except:
            return None

if os.path.exists(filepath):
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Count pages
        pages = root.findall('diagram')
        result["num_pages"] = len(pages)
        
        all_text = []
        
        # Process pages
        for page in pages:
            content = page.text
            xml_content = None
            
            # Check if compressed
            if content and not content.strip().startswith('<'):
                decompressed = decompress_diagram(content)
                if decompressed:
                    xml_content = decompressed
            else:
                xml_content = content
                
            if xml_content:
                try:
                    # Wrap in root if needed
                    if not xml_content.strip().startswith('<mxGraphModel'):
                        xml_content = f"<root>{xml_content}</root>"
                    
                    page_root = ET.fromstring(xml_content)
                    
                    # Count shapes and edges
                    for cell in page_root.iter('mxCell'):
                        val = cell.get('value', '').lower()
                        style = cell.get('style', '').lower()
                        
                        if cell.get('vertex') == '1':
                            result["total_shapes"] += 1
                            if 'swimlane' in style or 'table' in style:
                                result["swimlanes_found"] += 1
                        elif cell.get('edge') == '1':
                            result["total_edges"] += 1
                            
                        if val:
                            # Strip HTML tags
                            clean_val = re.sub(r'<[^>]+>', ' ', val)
                            all_text.append(clean_val)
                            
                except Exception as e:
                    pass

        # Analyze gathered text
        full_text = " ".join(all_text).lower()
        result["text_content"] = full_text[:5000] # Truncate for log
        
        # Check Phase Keywords
        for p in PHASES:
            if p in full_text:
                result["phases_found"].append(p)
                
        # Check Lane Keywords
        for l in LANES:
            if l in full_text:
                result["lanes_found"].append(l)
                
        # Check Content Keywords
        for c in CONTENT_KEYWORDS:
            if c in full_text:
                result["content_keywords_found"].append(c)
                
        # Check Page 2 specific keywords
        for k in PAGE2_KEYWORDS:
            if k in full_text:
                result["page2_keywords_found"].append(k)

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "png_width": $PNG_WIDTH,
    "analysis": $(cat /tmp/journey_analysis.json 2>/dev/null || echo "{}")
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="