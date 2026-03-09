#!/bin/bash
set -e
echo "=== Exporting Journal Manuscript Reformat Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if file exists and extract metadata
OUTPUT_FILE="/home/ga/Documents/manuscript_formatted.odt"
INPUT_FILE="/home/ga/Documents/manuscript_draft.odt"

# Check timestamp
FILE_MODIFIED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# 3. Analyze the ODT file using Python
# We extract XML and parse it to check verification criteria
echo "Analyzing ODT structure..."

python3 << 'PY_EOF'
import zipfile
import json
import os
import re
import sys

# Output structure
result = {
    "file_exists": False,
    "file_size": 0,
    "modified_during_task": False,
    "margins_correct": False,
    "font_correct": False,
    "line_spacing_correct": False,
    "line_numbering_enabled": False,
    "header_correct": False,
    "footer_has_page_numbers": False,
    "h1_count": 0,
    "h2_count": 0,
    "hanging_indent_count": 0,
    "raw_margins": {},
    "raw_font": "",
    "error": None
}

output_path = "/home/ga/Documents/manuscript_formatted.odt"
task_start_str = os.environ.get("TASK_START", "0")
task_start = int(task_start_str) if task_start_str.isdigit() else 0

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    if os.path.getmtime(output_path) > task_start:
        result["modified_during_task"] = True

    try:
        with zipfile.ZipFile(output_path, 'r') as z:
            content_xml = z.read('content.xml').decode('utf-8')
            styles_xml = z.read('styles.xml').decode('utf-8')
            
            # --- Check 1: Margins (2.54cm or 1in) ---
            # Margins are usually in styles.xml under style:page-layout-properties
            # Regex for margin attributes
            margins = re.findall(r'fo:margin-\w+="([^"]+)"', styles_xml)
            # Count valid margins (approx 2.54cm or 1in)
            valid_margin_count = 0
            for m in margins:
                # normalize: remove spaces
                m = m.replace(" ", "")
                if "2.54cm" in m or "1in" in m:
                    valid_margin_count += 1
            
            # We need at least 4 valid margins (top, bottom, left, right) in the PageLayout
            if valid_margin_count >= 4:
                result["margins_correct"] = True
            result["raw_margins"] = margins[:4]

            # --- Check 2: Font (Times New Roman) ---
            # Look for style:font-name="Times New Roman" in styles.xml or content.xml
            if 'Times New Roman' in styles_xml or 'Times New Roman' in content_xml:
                result["font_correct"] = True
                result["raw_font"] = "Times New Roman found"
            
            # --- Check 3: Line Spacing (200% or 2.0) ---
            # fo:line-height="200%" or "2"
            if 'fo:line-height="200%"' in styles_xml or 'fo:line-height="200%"' in content_xml:
                 result["line_spacing_correct"] = True
            
            # --- Check 4: Line Numbering ---
            # <text:linenumbering-configuration text:number-lines="true" ...> in styles.xml
            if 'text:number-lines="true"' in styles_xml:
                result["line_numbering_enabled"] = True
            
            # --- Check 5: Header Content ---
            # "Microplastic Accumulation" in header style
            # Header content is often in styles.xml inside <style:header>
            header_content = re.search(r'<style:header>(.*?)</style:header>', styles_xml, re.DOTALL)
            if header_content:
                text_in_header = header_content.group(1)
                if "Microplastic" in text_in_header:
                    result["header_correct"] = True
            
            # --- Check 6: Footer Page Numbers ---
            # <text:page-number> inside <style:footer>
            footer_content = re.search(r'<style:footer>(.*?)</style:footer>', styles_xml, re.DOTALL)
            if footer_content:
                if "text:page-number" in footer_content.group(1):
                    result["footer_has_page_numbers"] = True

            # --- Check 7: Headings (Structure) ---
            # Count <text:h text:outline-level="1"> and "2" in content.xml
            result["h1_count"] = content_xml.count('text:outline-level="1"')
            result["h2_count"] = content_xml.count('text:outline-level="2"')
            
            # --- Check 8: Hanging Indents ---
            # Look for paragraphs with margin-left > 0 and text-indent < 0
            # This logic is a bit heuristic for regex, checking for negative indent usage
            # pattern: fo:margin-left="1.27cm" fo:text-indent="-1.27cm"
            # We search for any text-indent starting with "-"
            hanging_indents = re.findall(r'fo:text-indent="-', content_xml)
            if not hanging_indents:
                hanging_indents = re.findall(r'fo:text-indent="-', styles_xml)
            
            # If we find style definitions with negative indent, we check if they are used
            # For simplicity, if we see significant usage of negative indent styles:
            result["hanging_indent_count"] = len(hanging_indents)
            
    except Exception as e:
        result["error"] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PY_EOF

# 4. Handle permissions and output
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="