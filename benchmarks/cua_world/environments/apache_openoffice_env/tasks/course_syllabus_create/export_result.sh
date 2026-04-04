#!/bin/bash
# Export script for Course Syllabus Create task
echo "=== Exporting Course Syllabus Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze the result file using Python
# We use Python here because parsing XML from the ODT zip is complex in pure bash
python3 << 'PYEOF'
import json
import os
import zipfile
import re
import datetime

output_file = "/home/ga/Documents/ENVS410_Syllabus_Fall2024.odt"
task_start_file = "/tmp/task_start_time.txt"

result = {
    "file_exists": False,
    "file_size": 0,
    "created_during_task": False,
    "heading1_count": 0,
    "heading2_count": 0,
    "has_toc": False,
    "has_page_numbers": False,
    "table_count": 0,
    "max_table_rows": 0,
    "content_check": {
        "has_course_code": False,
        "has_instructor": False,
        "has_domain_term": False,
        "has_university": False,
        "has_grading_pct": False,
        "has_textbook": False
    },
    "parse_error": None,
    "timestamp": datetime.datetime.now().isoformat()
}

# Check file existence
if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    # Check timestamp
    try:
        mtime = os.path.getmtime(output_file)
        if os.path.exists(task_start_file):
            with open(task_start_file, 'r') as f:
                start_time = int(f.read().strip())
            result["created_during_task"] = mtime > start_time
    except Exception:
        pass

    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # Read content.xml
            content = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Count Headings (Outline levels)
            # Use regex to find <text:h ... outline-level="1">
            result["heading1_count"] = len(re.findall(r'<text:h\b[^>]*text:outline-level="1"', content))
            result["heading2_count"] = len(re.findall(r'<text:h\b[^>]*text:outline-level="2"', content))
            
            # Check for TOC
            result["has_toc"] = 'text:table-of-content' in content
            
            # Count Tables
            tables = re.findall(r'<table:table\b[^>]*>', content)
            result["table_count"] = len(tables)
            
            # Count rows in the largest table (looking for 16-week schedule)
            max_rows = 0
            # Extract each table block to count rows within it
            table_blocks = re.findall(r'<table:table\b.*?</table:table>', content, re.DOTALL)
            for tb in table_blocks:
                rows = len(re.findall(r'<table:table-row\b', tb))
                if rows > max_rows:
                    max_rows = rows
            result["max_table_rows"] = max_rows
            
            # Extract plain text for content checking
            plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
            
            result["content_check"]["has_course_code"] = "envs 410" in plain_text
            result["content_check"]["has_instructor"] = ("al-rashid" in plain_text or "samira" in plain_text)
            result["content_check"]["has_domain_term"] = "urban ecology" in plain_text
            result["content_check"]["has_university"] = "portland state" in plain_text
            
            # Check for grading percentages (e.g., 30%, 15%)
            grading_pcts = ["10%", "15%", "25%", "30%", "5%"]
            found_pcts = sum(1 for p in grading_pcts if p in plain_text)
            result["content_check"]["has_grading_pct"] = found_pcts >= 3
            
            result["content_check"]["has_textbook"] = ("forman" in plain_text or "beatley" in plain_text)
            
            # Check for page numbers (can be in content.xml or styles.xml)
            if 'text:page-number' in content:
                result["has_page_numbers"] = True
            else:
                # Check styles.xml for footer definition containing page number
                if 'styles.xml' in zf.namelist():
                    styles = zf.read('styles.xml').decode('utf-8', errors='replace')
                    if 'text:page-number' in styles:
                        result["has_page_numbers"] = True
                    # Also check for simple footer presence
                    if '<style:footer' in styles:
                        result["has_footer_style"] = True

    except Exception as e:
        result["parse_error"] = str(e)

# Write result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="