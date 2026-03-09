#!/bin/bash
# Export script for dot_compliance_manual task

echo "=== Exporting DOT Compliance Manual Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target output file
OUTPUT_FILE="/home/ga/Documents/GLFL_DOT_Compliance_Manual.odt"

# Python script to analyze ODT content and export JSON
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import datetime

output_file = "/home/ga/Documents/GLFL_DOT_Compliance_Manual.odt"
task_start_ts = int(os.environ.get('TASK_START', 0))

result = {
    "file_exists": False,
    "file_size": 0,
    "file_created_during_task": False,
    "heading1_count": 0,
    "heading2_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "has_footer": False,
    "table_count": 0,
    "paragraph_count": 0,
    "content_check": {
        "company_name": False,
        "usdot": False,
        "mc_number": False,
        "cfr_references": 0,
        "regulatory_terms": 0
    },
    "parse_error": None,
    "export_timestamp": datetime.datetime.now().isoformat()
}

if not os.path.exists(output_file):
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    print("File not found")
    exit(0)

# Check timestamps
file_mtime = int(os.path.getmtime(output_file))
result["file_exists"] = True
result["file_size"] = os.path.getsize(output_file)
result["file_created_during_task"] = file_mtime >= task_start_ts

try:
    with zipfile.ZipFile(output_file, 'r') as zf:
        names = zf.namelist()
        content = zf.read('content.xml').decode('utf-8', errors='replace')

        # Structure Checks
        result["heading1_count"] = len(re.findall(r'<text:h\b[^>]*text:outline-level="1"', content))
        result["heading2_count"] = len(re.findall(r'<text:h\b[^>]*text:outline-level="2"', content))
        result["has_toc"] = 'text:table-of-content' in content
        result["table_count"] = len(re.findall(r'<table:table\b', content))
        
        # Paragraph count (exclude headings to approximate body text)
        all_paras = len(re.findall(r'<text:p\b', content))
        result["paragraph_count"] = all_paras

        # Content Keyword Checks
        plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
        
        # Identity
        result["content_check"]["company_name"] = ("great lakes freight" in plain_text or "glfl" in plain_text)
        result["content_check"]["usdot"] = "1847293" in plain_text
        result["content_check"]["mc_number"] = "682041" in plain_text
        
        # Regulatory References
        cfr_matches = re.findall(r'49 cfr part \d{3}', plain_text)
        # Unique parts
        unique_parts = set([m.split(' ')[-1] for m in cfr_matches])
        result["content_check"]["cfr_references"] = len(unique_parts)
        
        # Regulatory Terms
        terms = [
            "hours of service", "driver qualification", "controlled substances", 
            "drug and alcohol", "vehicle inspection", "maintenance", 
            "hazardous material", "hazmat", "accident register"
        ]
        found_terms = 0
        for term in terms:
            if term in plain_text:
                found_terms += 1
        result["content_check"]["regulatory_terms"] = found_terms

        # Footer/Page Numbers Check
        # Check both content.xml (sometimes used) and styles.xml (usual location for footers)
        has_pn_content = 'text:page-number' in content
        has_pn_styles = False
        has_footer = False
        
        if 'styles.xml' in names:
            styles = zf.read('styles.xml').decode('utf-8', errors='replace')
            has_footer = '<style:footer' in styles or '<text:footer' in styles
            has_pn_styles = 'text:page-number' in styles
            
        result["has_footer"] = has_footer
        result["has_page_numbers"] = has_pn_content or has_pn_styles

except Exception as e:
    result["parse_error"] = str(e)

print(json.dumps(result, indent=2))
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="