#!/bin/bash
# export_result.sh for paperback_book_layout
# Extracts XML from ODT and analyzes formatting

echo "=== Exporting Paperback Book Layout Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check File Existence and Timestamp
OUTPUT_FILE="/home/ga/Documents/The_Echoing_Void_Formatted.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# 3. Parse ODT Content (Python)
# We use a python script to unzip the ODT and parse styles.xml and content.xml
python3 << 'PYEOF'
import zipfile
import json
import os
import re

output_file = "/home/ga/Documents/The_Echoing_Void_Formatted.odt"
result = {
    "file_exists": False,
    "page_width": None,
    "page_height": None,
    "margin_left": None,
    "margin_right": None,
    "margin_top": None,
    "margin_bottom": None,
    "print_orientation": None,
    "first_line_indent": None,
    "paragraph_margin_bottom": None,
    "header_content_left": None,
    "header_content_right": None,
    "has_header_left_style": False,
    "error": None
}

if os.path.exists(output_file):
    result["file_exists"] = True
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # --- Parse styles.xml for Page Layout ---
            styles_xml = zf.read('styles.xml').decode('utf-8', errors='replace')
            
            # Find the default page layout properties
            # Look for <style:page-layout-properties ...>
            # We are looking for the Standard page layout or the one used by default
            
            # Extract page geometry
            # Regex to find page geometry attributes
            width_match = re.search(r'fo:page-width="([^"]+)"', styles_xml)
            if width_match: result["page_width"] = width_match.group(1)
            
            height_match = re.search(r'fo:page-height="([^"]+)"', styles_xml)
            if height_match: result["page_height"] = height_match.group(1)
            
            # Extract margins
            margin_l_match = re.search(r'fo:margin-left="([^"]+)"', styles_xml)
            if margin_l_match: result["margin_left"] = margin_l_match.group(1)
            
            margin_r_match = re.search(r'fo:margin-right="([^"]+)"', styles_xml)
            if margin_r_match: result["margin_right"] = margin_r_match.group(1)

            margin_t_match = re.search(r'fo:margin-top="([^"]+)"', styles_xml)
            if margin_t_match: result["margin_top"] = margin_t_match.group(1)

            margin_b_match = re.search(r'fo:margin-bottom="([^"]+)"', styles_xml)
            if margin_b_match: result["margin_bottom"] = margin_b_match.group(1)

            # Check for mirrored pages configuration
            # Often indicated by style:print-orientation="landscape" (rare for book) or style:page-usage="mirrored"
            # Or just the presence of <style:header-left> in the master page
            
            if 'style:page-usage="mirrored"' in styles_xml:
                result["print_orientation"] = "mirrored"
            
            # Check headers
            # In ODT, left headers are usually in <style:header-left>
            result["has_header_left_style"] = '<style:header-left' in styles_xml
            
            # --- Parse content.xml for Text and Headers content ---
            # NOTE: Header content is often stored in styles.xml if it's part of the master page, 
            # BUT sometimes the actual text is referenced.
            # Let's check styles.xml for header text first as it is part of the page style definition usually.
            
            # Extract text content from styles.xml (where headers usually live)
            # We are looking for the text inside <style:header> and <style:header-left>
            
            # Simple extraction of text within header tags
            header_left_match = re.search(r'<style:header-left>(.*?)</style:header-left>', styles_xml, re.DOTALL)
            if header_left_match:
                left_content = re.sub(r'<[^>]+>', '', header_left_match.group(1))
                result["header_content_left"] = left_content.strip()
            
            header_right_match = re.search(r'<style:header>(.*?)</style:header>', styles_xml, re.DOTALL)
            if header_right_match:
                right_content = re.sub(r'<[^>]+>', '', header_right_match.group(1))
                result["header_content_right"] = right_content.strip()
            
            # --- Parse Paragraph Styles (content.xml or styles.xml) ---
            # We need to find the paragraph style used for the body text. 
            # This is complex because it could be "Text_20_body" or "Standard".
            # We'll look for any style that has text-indent.
            
            indent_match = re.search(r'fo:text-indent="([^"]+)"', styles_xml)
            if indent_match:
                result["first_line_indent"] = indent_match.group(1)
            else:
                # Check automatic styles in content.xml
                content_xml = zf.read('content.xml').decode('utf-8', errors='replace')
                indent_match_auto = re.search(r'fo:text-indent="([^"]+)"', content_xml)
                if indent_match_auto:
                    result["first_line_indent"] = indent_match_auto.group(1)

            # Check paragraph spacing (margin-bottom="0in")
            # This is hard to pinpoint exactly to the specific paragraph without deep parsing,
            # but we can look for the existence of 0 margin styles.
            zero_margin_match = re.search(r'fo:margin-bottom="0in"', styles_xml)
            if zero_margin_match:
                result["paragraph_margin_bottom"] = "0in"

    except Exception as e:
        result["error"] = str(e)

# Save result to file
with open('/tmp/analysis_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

# 4. Merge Results
python3 << 'PYEOF'
import json
import os

try:
    with open('/tmp/analysis_result.json', 'r') as f:
        analysis = json.load(f)
except:
    analysis = {}

final_result = {
    "file_exists": os.environ.get("FILE_EXISTS") == "true",
    "file_size": os.environ.get("FILE_SIZE"),
    "modified_during_task": os.environ.get("FILE_MODIFIED_DURING_TASK") == "true",
    "analysis": analysis
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_result, f, indent=2)
PYEOF

# 5. Clean up and set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="