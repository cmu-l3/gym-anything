#!/bin/bash
# Export script for genealogy_manuscript_index task
# Parses ODT XML to verify index marks, heading styles, and page numbers

echo "=== Exporting Genealogy Index Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/Documents/Holloway_Chapter4_Indexed.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# Python script to analyze ODT content
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys

output_file = "/home/ga/Documents/Holloway_Chapter4_Indexed.odt"
result_path = "/tmp/task_result.json"

data = {
    "file_exists": False,
    "file_size": 0,
    "heading_style_applied": False,
    "has_page_numbers": False,
    "index_section_exists": False,
    "index_marks_count": 0,
    "index_content_verification": [],
    "marked_terms_found": [],
    "generated_index_text": ""
}

# TERMS TO CHECK (Must match task.json)
TERMS = [
    "Jeremiah Holloway", "Martha Holloway", "Cumberland Gap", "Oxen",
    "Fort Laramie", "Independence Rock", "Chimney Rock", "Oregon Trail",
    "Cholera", "Wagon"
]

if os.path.exists(output_file):
    data["file_exists"] = True
    data["file_size"] = os.path.getsize(output_file)
    
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # 1. READ CONTENT.XML
            content = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Check Heading 1 Style on Title
            # Look for Chapter 4 title with Heading style (text:style-name="Heading_20_1" or outline-level=1)
            # Regex to find the paragraph containing "Chapter 4" and check attributes
            title_regex = re.compile(r'<text:[hp][^>]*?>(?:(?!</text:[hp]>).)*Chapter 4: The Crossing.*?</text:[hp]>', re.IGNORECASE)
            title_match = title_regex.search(content)
            
            if title_match:
                title_tag = title_match.group(0)
                if 'outline-level="1"' in title_tag or 'style-name="Heading_20_1"' in title_tag:
                    data["heading_style_applied"] = True
            
            # Check for Alphabetical Index Marks
            # Format: <text:alphabetical-index-mark-start .../> or <text:alphabetical-index-mark .../>
            # Note: OpenOffice uses <text:alphabetical-index-mark text:string-value="Term" .../>
            marks = re.findall(r'<text:alphabetical-index-mark\b', content)
            data["index_marks_count"] = len(marks)
            
            # Extract specific terms marked
            # We look for text:string-value="Term"
            for term in TERMS:
                # Simple check if term appears inside an index mark tag
                # This is a robust heuristic for "is this term marked?"
                term_marked = False
                # Regex looking for the mark containing the term
                # <text:alphabetical-index-mark ... text:string-value="Jeremiah Holloway" .../>
                if re.search(r'<text:alphabetical-index-mark[^>]*text:string-value="'+re.escape(term)+r'"', content):
                    term_marked = True
                data["marked_terms_found"].append({"term": term, "marked": term_marked})

            # Check for Generated Index Section
            # <text:alphabetical-index ...> ... </text:alphabetical-index>
            if '<text:alphabetical-index ' in content:
                data["index_section_exists"] = True
                
                # Extract text INSIDE the index section to verify it was updated/generated
                # Find start and end indices of the index tag
                start_idx = content.find('<text:alphabetical-index ')
                end_idx = content.find('</text:alphabetical-index>', start_idx)
                if start_idx != -1 and end_idx != -1:
                    index_body = content[start_idx:end_idx]
                    # Clean tags to get plain text of the index
                    plain_index = re.sub(r'<[^>]+>', ' ', index_body)
                    data["generated_index_text"] = plain_index[:1000] # Save preview
                    
                    # Verify terms appear in the generated index
                    for term in TERMS:
                        in_index = term in plain_index
                        data["index_content_verification"].append({"term": term, "in_generated_index": in_index})

            # 2. READ STYLES.XML (for Footer/Page Numbers)
            if 'styles.xml' in zf.namelist():
                styles = zf.read('styles.xml').decode('utf-8', errors='replace')
                # Check for footer style definition containing page number
                # <style:footer> ... <text:page-number .../> ... </style:footer>
                # Simplified check: Look for page-number tag
                if '<text:page-number' in styles or '<text:page-number' in content:
                    data["has_page_numbers"] = True

    except Exception as e:
        data["error"] = str(e)

# Write result
with open(result_path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

# Permission fix
chmod 666 "$RESULT_JSON" 2>/dev/null || sudo chmod 666 "$RESULT_JSON"

echo "Result JSON generated:"
cat "$RESULT_JSON"
echo "=== Export Complete ==="