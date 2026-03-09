#!/bin/bash
echo "=== Exporting USPTO Patent Format Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# 2. Define paths
OUTPUT_FILE="/home/ga/Documents/NeuroSync_Patent_App.odt"
RESULT_JSON="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Python script to analyze the ODT structure
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys
from datetime import datetime

output_file = "/home/ga/Documents/NeuroSync_Patent_App.odt"
task_start = int(sys.argv[1]) if len(sys.argv) > 1 else 0

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "line_numbering_enabled": False,
    "margins_correct": False,
    "double_spacing_detected": False,
    "claims_list_detected": False,
    "abstract_page_break": False,
    "font_size_12_detected": False,
    "headings_bold_caps": False,
    "details": {}
}

if os.path.exists(output_file):
    result["file_exists"] = True
    mtime = int(os.path.getmtime(output_file))
    if mtime > task_start:
        result["file_created_during_task"] = True
    
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # Read styles.xml for page layout and line numbering
            styles_xml = zf.read('styles.xml').decode('utf-8', errors='ignore')
            
            # Read content.xml for text formatting and structure
            content_xml = zf.read('content.xml').decode('utf-8', errors='ignore')
            
            # --- CHECK 1: LINE NUMBERING ---
            # Look for <text:linenumbering-configuration ... text:number-lines="true" ...>
            # Or simplified regex for the attribute presence in styles
            if 'text:number-lines="true"' in styles_xml or 'text:number-lines="true"' in content_xml:
                result["line_numbering_enabled"] = True
            
            # --- CHECK 2: MARGINS ---
            # Look for fo:margin="1in" or "2.54cm" or individual margins
            # <style:page-layout-properties fo:page-width="8.5in" fo:page-height="11in" ... fo:margin-top="1in" ...>
            margins_found = re.findall(r'fo:margin-?\w*="([^"]+)"', styles_xml)
            correct_margins = 0
            for m in margins_found:
                if m in ["1in", "1.0in", "2.54cm", "2.540cm"]:
                    correct_margins += 1
            # If we see at least 4 valid margin settings (Top/Bot/Left/Right or shorthand), pass
            if correct_margins >= 1: # Usually it's fo:margin="1in" appearing once or 4 separate
                result["margins_correct"] = True
            
            # --- CHECK 3: DOUBLE SPACING ---
            # fo:line-height="200%" inside paragraph styles
            if 'fo:line-height="200%"' in content_xml or 'fo:line-height="200%"' in styles_xml:
                result["double_spacing_detected"] = True
            
            # --- CHECK 4: CLAIMS LIST ---
            # Claims section should contain a list. Look for <text:list> after "CLAIMS"
            # Extract plain text to find relative position, or check for list existence
            if '<text:list' in content_xml:
                # Naive check: does the doc contain a list?
                result["claims_list_detected"] = True
            
            # --- CHECK 5: ABSTRACT PAGE BREAK ---
            # Look for page break before Abstract
            # Regex for "ABSTRACT" and check preceding tags for soft-page-break or style:page-break
            # Find the text:h or text:p containing "ABSTRACT"
            abstract_match = re.search(r'(<text:h[^>]*>ABSTRACT</text:h>|<text:p[^>]*>ABSTRACT</text:p>)', content_xml)
            if abstract_match:
                # Check for page break in the style of this paragraph OR an explicit break before it
                # OpenOffice often uses a style with fo:break-before="page"
                style_name_match = re.search(r'text:style-name="([^"]+)"', abstract_match.group(1))
                if style_name_match:
                    style_name = style_name_match.group(1)
                    # Check if this style has break-before="page" in content.xml or styles.xml
                    style_def_pattern = r'<style:style[^>]*style:name="' + re.escape(style_name) + r'"[^>]*>.*?</style:style>'
                    
                    # Search in both files
                    style_def = re.search(style_def_pattern, content_xml, re.DOTALL) or re.search(style_def_pattern, styles_xml, re.DOTALL)
                    
                    if style_def and 'fo:break-before="page"' in style_def.group(0):
                        result["abstract_page_break"] = True
            
            # Explicit soft page break check
            if '<text:soft-page-break/>' in content_xml:
                # We assume if they used a page break, it was likely for the Abstract or Claims
                # This is a weak signal but acceptable for "hard" task where formatting is key
                pass 

            # --- CHECK 6: FONT SIZE ---
            if 'fo:font-size="12pt"' in content_xml or 'fo:font-size="12pt"' in styles_xml:
                result["font_size_12_detected"] = True
            
            # --- CHECK 7: HEADINGS BOLD ---
            # Check for styles with bold weight
            if 'fo:font-weight="bold"' in content_xml or 'fo:font-weight="bold"' in styles_xml:
                result["headings_bold_caps"] = True

    except Exception as e:
        result["details"]["error"] = str(e)

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF "$TASK_START"

# 4. Handle permission/ownership of the result file
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Export complete. Result:"
cat "$RESULT_JSON"