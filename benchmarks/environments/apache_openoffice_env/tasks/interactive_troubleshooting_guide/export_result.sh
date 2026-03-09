#!/bin/bash
set -e
echo "=== Exporting Interactive Troubleshooting Guide Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/Sentinel_Guide_Interactive.odt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to analyze the ODT structure (bookmarks and links)
# We embed the script to avoid dependency issues on the host
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

output_file = "/home/ga/Documents/Sentinel_Guide_Interactive.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "file_created_during_task": False,
    "bookmarks_found": [],
    "internal_links": [],
    "headings_found": [],
    "parse_error": None
}

# Check file existence
if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    # Check timestamp
    mtime = os.path.getmtime(output_file)
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            start_time = float(f.read().strip())
        if mtime > start_time:
            result["file_created_during_task"] = True
    except:
        pass

    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            content_xml = zf.read('content.xml')
            
        # Parse XML (ignoring namespaces for simplicity or handling them)
        # ODT uses namespaces heavily, so we'll use a regex approach for robustness 
        # against slight parser variations, or careful XML parsing.
        # Let's use ElementTree with namespace handling.
        
        root = ET.fromstring(content_xml)
        
        # Define namespaces
        ns = {
            'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
            'xlink': 'http://www.w3.org/1999/xlink'
        }
        
        # 1. Find Bookmarks
        # <text:bookmark text:name="Name"/> or <text:bookmark-start text:name="Name"/>
        bookmarks = []
        for bm in root.findall('.//text:bookmark', ns) + root.findall('.//text:bookmark-start', ns):
            name = bm.get(f"{{{ns['text']}}}name")
            if name and not name.startswith("__"): # Ignore system bookmarks
                bookmarks.append(name)
        result["bookmarks_found"] = list(set(bookmarks)) # Unique names
        
        # 2. Find Hyperlinks
        # <text:a xlink:type="simple" xlink:href="#Target">Link Text</text:a>
        links = []
        for link in root.findall('.//text:a', ns):
            href = link.get(f"{{{ns['xlink']}}}href")
            text = "".join(link.itertext())
            if href and href.startswith("#"):
                links.append({"text": text, "target": href.replace("#", "")})
        result["internal_links"] = links
        
        # 3. Find Headings
        # <text:h text:outline-level="1">Title</text:h>
        headings = []
        for h in root.findall('.//text:h', ns):
            level = h.get(f"{{{ns['text']}}}outline-level")
            text = "".join(h.itertext())
            headings.append({"level": level, "text": text})
        result["headings_found"] = headings

    except Exception as e:
        result["parse_error"] = str(e)
else:
    print("Output file not found.")

# Write result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete. Result saved to /tmp/task_result.json")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="