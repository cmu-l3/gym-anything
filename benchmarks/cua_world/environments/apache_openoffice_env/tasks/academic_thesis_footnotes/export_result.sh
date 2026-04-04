#!/bin/bash
# Export script for academic_thesis_footnotes task
# Analyzes the ODT file for:
# 1. Presence of text:note elements (footnotes)
# 2. Content of those notes (matching citations)
# 3. Heading styles on specific text
# 4. Bibliography paragraph styling (hanging indent)
# 5. Page numbers in footer

echo "=== Exporting Academic Thesis Result ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/Chapter_2_Final.odt"
RESULT_FILE="/tmp/task_result.json"

take_screenshot /tmp/task_final.png

# Run Python analysis script
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import datetime

output_file = "/home/ga/Documents/Chapter_2_Final.odt"
result = {
    "file_exists": False,
    "footnote_count": 0,
    "footnote_contents": [],
    "headings_found": [],
    "bibliography_hanging_indent": False,
    "page_numbers_present": False,
    "timestamp": datetime.datetime.now().isoformat()
}

if os.path.exists(output_file):
    result["file_exists"] = True
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            content = zf.read('content.xml').decode('utf-8', errors='replace')
            styles = zf.read('styles.xml').decode('utf-8', errors='replace')

            # 1. Count footnotes (text:note elements)
            notes = re.findall(r'<text:note\b.*?>(.*?)</text:note>', content, re.DOTALL)
            result["footnote_count"] = len(notes)

            # 2. Extract content of footnotes
            # We strip XML tags to get raw text for verification
            for note_xml in notes:
                # Inside text:note is usually text:note-body -> text:p
                raw_text = re.sub(r'<[^>]+>', ' ', note_xml)
                clean_text = re.sub(r'\s+', ' ', raw_text).strip()
                result["footnote_contents"].append(clean_text)

            # 3. Check Headings (Heading 1)
            # Looking for text:h with outline-level="1"
            # And extracting text to see if it matches "Chapter 2..." or "Bibliography"
            headings = re.findall(r'<text:h[^>]+text:outline-level="1"[^>]*>(.*?)</text:h>', content, re.DOTALL)
            for h in headings:
                result["headings_found"].append(re.sub(r'<[^>]+>', '', h).strip())

            # 4. Check Bibliography formatting (Hanging Indent)
            # Find the Bibliography section.
            # In ODT, hanging indent is defined in automatic-styles (content.xml) or styles.xml
            # It looks like: margin-left="X" text-indent="-X" (where X > 0)
            
            # Simple check: scan for any style definition with negative text-indent
            # This is a heuristic. A strict check would map paragraphs to styles.
            # Given the task, if a negative text-indent exists in content.xml styles, it's likely the agent applied it.
            has_hanging = False
            style_defs = re.findall(r'<style:paragraph-properties[^>]+>', content)
            for style in style_defs:
                # Check for negative text-indent
                ti_match = re.search(r'text-indent="(-[\d\.]+\w+)"', style)
                ml_match = re.search(r'margin-left="([\d\.]+\w+)"', style)
                if ti_match and ml_match:
                    # Check if they roughly offset (margin > 0, indent < 0)
                    has_hanging = True
            
            result["bibliography_hanging_indent"] = has_hanging

            # 5. Check Page Numbers
            # Usually <text:page-number/> inside <style:footer> in styles.xml
            has_pagenum_style = 'text:page-number' in styles
            has_pagenum_content = 'text:page-number' in content
            result["page_numbers_present"] = has_pagenum_style or has_pagenum_content

    except Exception as e:
        result["error"] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Move result to safe location with permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="