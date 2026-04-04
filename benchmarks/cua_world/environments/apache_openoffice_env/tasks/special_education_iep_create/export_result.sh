#!/bin/bash
# Export script for special_education_iep_create
# Analyzes the ODT file structure and content

echo "=== Exporting IEP Task Result ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final visual state
take_screenshot /tmp/task_final.png

# Paths
OUTPUT_FILE="/home/ga/Documents/IEP_Reyes-Contreras_Mateo_2024.odt"
RESULT_JSON="/tmp/task_result.json"

# Check if app is running
APP_RUNNING="false"
if pgrep -f "soffice" > /dev/null; then
    APP_RUNNING="true"
fi

# Close OpenOffice to ensure file is saved/unlocked
pkill -f soffice 2>/dev/null || true
sleep 2

# Analyze the ODT file using Python
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys

output_file = "/home/ga/Documents/IEP_Reyes-Contreras_Mateo_2024.odt"
result_file = "/tmp/task_result.json"

data = {
    "file_exists": False,
    "file_size": 0,
    "has_toc": False,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "has_page_numbers": False,
    "paragraph_count": 0,
    "student_name_found": False,
    "iep_terms_found": False,
    "assessment_data_found": False,
    "timestamp": "",
    "app_running": False
}

# Pass bash variable for app running
if os.environ.get("APP_RUNNING") == "true":
    data["app_running"] = True

if os.path.exists(output_file):
    data["file_exists"] = True
    data["file_size"] = os.path.getsize(output_file)
    
    try:
        with zipfile.ZipFile(output_file, 'r') as z:
            # Read content.xml
            content_xml = z.read('content.xml').decode('utf-8', errors='ignore')
            
            # Read styles.xml (often where footers define page numbers)
            styles_xml = ""
            if 'styles.xml' in z.namelist():
                styles_xml = z.read('styles.xml').decode('utf-8', errors='ignore')

            # 1. Check for Table of Contents
            if 'text:table-of-content' in content_xml:
                data["has_toc"] = True

            # 2. Count Headings (looking for text:outline-level)
            # Heading 1
            h1_matches = re.findall(r'text:outline-level="1"', content_xml)
            data["heading1_count"] = len(h1_matches)
            
            # Heading 2
            h2_matches = re.findall(r'text:outline-level="2"', content_xml)
            data["heading2_count"] = len(h2_matches)

            # 3. Count Tables
            table_matches = re.findall(r'<table:table\b', content_xml)
            data["table_count"] = len(table_matches)

            # 4. Check for Page Numbers
            # Usually <text:page-number> inside styles.xml (footer) or content.xml
            if 'text:page-number' in content_xml or 'text:page-number' in styles_xml:
                data["has_page_numbers"] = True

            # 5. Text Analysis
            # Strip tags to get raw text
            raw_text = re.sub(r'<[^>]+>', ' ', content_xml).lower()
            
            # Paragraph count (approximate by text:p tags)
            data["paragraph_count"] = len(re.findall(r'<text:p\b', content_xml))

            # Student Name
            if "reyes" in raw_text or "mateo" in raw_text:
                data["student_name_found"] = True
            
            # IEP Terms
            terms = ["present levels", "annual goal", "accommodation", "least restrictive", "related services", "idea"]
            term_count = sum(1 for t in terms if t in raw_text)
            if term_count >= 3:
                data["iep_terms_found"] = True

            # Assessment Data
            assessments = ["woodcock", "dibels", "standard score", "78", "fluency"]
            ass_count = sum(1 for a in assessments if a in raw_text)
            if ass_count >= 2:
                data["assessment_data_found"] = True

    except Exception as e:
        data["error"] = str(e)

# Write result
with open(result_file, 'w') as f:
    json.dump(data, f, indent=2)

print("Analysis complete.")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="