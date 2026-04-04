#!/bin/bash
echo "=== Exporting Forensic Report Result ==="
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (Trajectory Evidence)
take_screenshot /tmp/task_final.png

# 2. Python Script to Analyze the ODT File
# We use Python here because bash XML parsing is fragile
cat << 'EOF' > /tmp/analyze_odt.py
import zipfile
import re
import json
import os
import sys

OUTPUT_FILE = "/home/ga/Documents/Forensic_Report_Case_442.odt"
RESULT_FILE = "/tmp/task_result.json"
TASK_START_FILE = "/tmp/task_start_time.txt"

result = {
    "file_exists": False,
    "file_size": 0,
    "created_during_task": False,
    "h1_count": 0,
    "h2_count": 0,
    "table_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "contains_case_number": False,
    "contains_hash": False,
    "contains_path": False,
    "monospace_fonts_detected": False,
    "error": None
}

try:
    if os.path.exists(OUTPUT_FILE):
        result["file_exists"] = True
        result["file_size"] = os.path.getsize(OUTPUT_FILE)
        
        # Check timestamp
        if os.path.exists(TASK_START_FILE):
            with open(TASK_START_FILE, 'r') as f:
                start_time = int(f.read().strip())
            file_mtime = int(os.path.getmtime(OUTPUT_FILE))
            if file_mtime > start_time:
                result["created_during_task"] = True

        # Open ODT (it's a zip)
        with zipfile.ZipFile(OUTPUT_FILE, 'r') as z:
            
            # --- Analyze content.xml ---
            content_xml = z.read('content.xml').decode('utf-8', errors='ignore')
            
            # Count Headings (text:h)
            result["h1_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="1"', content_xml))
            result["h2_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="2"', content_xml))
            
            # Count Tables
            result["table_count"] = len(re.findall(r'<table:table\b', content_xml))
            
            # Check TOC
            if 'text:table-of-content' in content_xml:
                result["has_toc"] = True
                
            # Extract plain text for content checks
            plain_text = re.sub(r'<[^>]+>', ' ', content_xml)
            
            # Content Checks
            if "CSF-2025-0442" in plain_text:
                result["contains_case_number"] = True
            if "a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890" in plain_text:
                result["contains_hash"] = True
            if "/var/www/html/wp-content/uploads/2024/11/b374k.php" in plain_text:
                result["contains_path"] = True

            # Monospace Font Detection (Heuristic)
            # 1. Check styles.xml for font declarations
            # 2. Check content.xml/styles.xml for style names that imply monospace
            styles_xml = ""
            if 'styles.xml' in z.namelist():
                styles_xml = z.read('styles.xml').decode('utf-8', errors='ignore')
                
            combined_xml = content_xml + styles_xml
            
            # Look for common monospace font names in font-face-decls
            mono_fonts = ["Courier", "Mono", "Consolas", "Fixed", "Source Code"]
            for font in mono_fonts:
                if f'style:font-name="{font}"' in combined_xml or f'svg:font-family="{font}"' in combined_xml:
                    result["monospace_fonts_detected"] = True
                    break
            
            # Also check for "Source Text" style which usually defaults to Mono
            if 'style:parent-style-name="Source_20_Text"' in combined_xml:
                 result["monospace_fonts_detected"] = True

            # --- Analyze styles.xml (for footer) ---
            if 'text:page-number' in styles_xml or 'text:page-number' in content_xml:
                result["has_page_numbers"] = True

except Exception as e:
    result["error"] = str(e)

with open(RESULT_FILE, 'w') as f:
    json.dump(result, f)
EOF

# Run the analysis
python3 /tmp/analyze_odt.py

# 3. Ensure permissions for the verifier
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json