#!/bin/bash
echo "=== Exporting Technical Manual Master Compile Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/Documents/AeroTurbine_Master.odm"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Prepare JSON export using Python to parse the ODM structure
# ODM files are ZIP archives containing content.xml
sudo -u ga python3 << PYEOF
import zipfile
import json
import os
import re
import sys
from xml.dom import minidom

output_path = "$OUTPUT_FILE"
task_start = int("$TASK_START")
result = {
    "file_exists": False,
    "is_odm_format": False,
    "link_count": 0,
    "linked_files": [],
    "has_toc": False,
    "has_title": False,
    "file_created_during_task": False
}

if os.path.exists(output_path):
    result["file_exists"] = True
    
    # Check timestamp
    mtime = int(os.path.getmtime(output_path))
    if mtime > task_start:
        result["file_created_during_task"] = True

    try:
        # OpenOffice files are ZIPs
        if zipfile.is_zipfile(output_path):
            with zipfile.ZipFile(output_path, 'r') as zf:
                # 1. Verify Mimetype
                try:
                    mimetype = zf.read('mimetype').decode('utf-8').strip()
                    if 'application/vnd.oasis.opendocument.text-master' in mimetype:
                        result["is_odm_format"] = True
                    # Some versions might save as regular text but with links, we'll be lenient if structure is right
                    elif 'application/vnd.oasis.opendocument.text' in mimetype:
                         result["is_odm_format"] = True # Accept regular ODT if it behaves like a master
                except:
                    pass

                # 2. Parse content.xml for structure
                content_xml = zf.read('content.xml')
                dom = minidom.parseString(content_xml)
                
                # Check for Linked Sections (text:section with xlink:href)
                # Note: Master documents use <text:section> with <text:section-source> usually,
                # or <text:section> with xlink:href depending on implementation
                
                # Method A: text:section-source (Standard for ODM)
                # <text:section text:style-name="Sect1" text:name="Section1">
                #   <text:section-source xlink:href="relative/path/to/file.odt" .../>
                # </text:section>
                
                links = []
                sections = dom.getElementsByTagName('text:section')
                for section in sections:
                    sources = section.getElementsByTagName('text:section-source')
                    for source in sources:
                        href = source.getAttribute('xlink:href')
                        if href:
                            links.append(href)
                
                result["link_count"] = len(links)
                result["linked_files"] = links
                
                # 3. Check for TOC
                tocs = dom.getElementsByTagName('text:table-of-content')
                if len(tocs) > 0:
                    result["has_toc"] = True
                
                # 4. Check for Title (simple text search in the XML for the specific string)
                # We convert bytes to string first
                xml_str = content_xml.decode('utf-8', errors='ignore')
                if "AeroTurbine 500-X Operator Manual" in xml_str:
                    result["has_title"] = True

    except Exception as e:
        result["error"] = str(e)

# Save to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="