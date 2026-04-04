#!/bin/bash
echo "=== Exporting Trade Fair Briefing Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

# Path to the expected output file
OUTPUT_FILE="/home/ga/Documents/Sterling_Hannover_Messe_Briefing_2025.odt"

# Use python to parse the ODT file and extract verification metrics
# We do this INSIDE the container because we have access to the file and python environment
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import datetime
import sys

output_file = "/home/ga/Documents/Sterling_Hannover_Messe_Briefing_2025.odt"
task_start_file = "/tmp/task_start_time.txt"

# Default result structure
result = {
    "file_exists": False,
    "file_size": 0,
    "created_after_start": False,
    "structure": {
        "h1_count": 0,
        "h2_count": 0,
        "table_count": 0,
        "toc_present": False,
        "page_numbers_present": False,
        "paragraph_count": 0
    },
    "content": {
        "delegates_found": [],
        "flight_found": False,
        "hotel_found": False,
        "partners_found": []
    },
    "timestamp": datetime.datetime.now().isoformat()
}

# Check file existence
if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    # Check timestamp
    try:
        with open(task_start_file, 'r') as f:
            start_time = int(f.read().strip())
        mtime = int(os.path.getmtime(output_file))
        if mtime > start_time:
            result["created_after_start"] = True
    except Exception:
        pass # Ignore timestamp errors if files missing

    # Parse ODT content
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # Read content.xml
            content_xml = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Read styles.xml (for footer/page numbers)
            styles_xml = ""
            if 'styles.xml' in zf.namelist():
                styles_xml = zf.read('styles.xml').decode('utf-8', errors='replace')

            # --- STRUCTURE CHECKS ---
            
            # Count headings
            # OpenOffice uses <text:h text:outline-level="1">
            result["structure"]["h1_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="1"', content_xml))
            result["structure"]["h2_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="2"', content_xml))
            
            # Count tables
            result["structure"]["table_count"] = len(re.findall(r'<table:table\b', content_xml))
            
            # Check TOC
            result["structure"]["toc_present"] = 'text:table-of-content' in content_xml
            
            # Check paragraphs (rough content volume)
            result["structure"]["paragraph_count"] = len(re.findall(r'<text:p\b', content_xml))

            # Check page numbers
            # Usually <text:page-number> inside styles.xml (footer) or content.xml
            result["structure"]["page_numbers_present"] = (
                'text:page-number' in content_xml or 
                'text:page-number' in styles_xml
            )

            # --- CONTENT CHECKS ---
            
            # Extract plain text for keyword searching
            plain_text = re.sub(r'<[^>]+>', ' ', content_xml).lower()
            
            # Check delegates
            delegates = ["albrecht", "oduya", "svensson", "delacroix"]
            for d in delegates:
                if d in plain_text:
                    result["content"]["delegates_found"].append(d)
            
            # Check flight and hotel
            if "lh 431" in plain_text or "lh431" in plain_text:
                result["content"]["flight_found"] = True
            
            if "courtyard" in plain_text:
                result["content"]["hotel_found"] = True
                
            # Check partners
            partners = ["siemens", "renishaw", "trumpf", "hexagon", "balluff", "schaeffler", "mitsubishi", "fraunhofer"]
            for p in partners:
                if p in plain_text:
                    result["content"]["partners_found"].append(p)

    except Exception as e:
        result["error"] = str(e)

# Write result to temp file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="