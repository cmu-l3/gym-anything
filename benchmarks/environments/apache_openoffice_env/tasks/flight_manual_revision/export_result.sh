#!/bin/bash
set -e
echo "=== Exporting Flight Manual Revision Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Check if output file exists
OUTPUT_FILE="/home/ga/Documents/GOM_Ch7_Rev05.odt"
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Output file not found!"
    # Write a minimal failure result
    cat > /tmp/task_result.json << EOF
{
    "file_exists": false,
    "file_saved_during_task": false,
    "error": "Output file not found"
}
EOF
    exit 0
fi

# 3. Check timestamps (Anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")

if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_SAVED_DURING_TASK="true"
else
    FILE_SAVED_DURING_TASK="false"
fi

# 4. Advanced ODT Parsing using Python
# We extract content and styles to verify specific formatting instructions
python3 << 'PYEOF'
import zipfile
import json
import re
import sys
import xml.etree.ElementTree as ET

odt_path = "/home/ga/Documents/GOM_Ch7_Rev05.odt"
result = {
    "file_exists": True,
    "file_saved_during_task": True, # set by bash, but we'll reconfirm in verifier
    "text_updated": False,
    "revision_bar_found": False,
    "warning_box_found": False,
    "warning_bold_found": False,
    "header_updated": False,
    "debug_info": []
}

try:
    with zipfile.ZipFile(odt_path, 'r') as zf:
        # Read Content
        content_xml = zf.read('content.xml').decode('utf-8')
        styles_xml = zf.read('styles.xml').decode('utf-8')
        
        # 1. Check Text Content
        # "tactile check of critical surfaces"
        target_text = "tactile check of critical surfaces"
        if target_text in content_xml:
            result["text_updated"] = True
        
        # 2. Check Revision Bar (Left Border)
        # Looking for a paragraph style with fo:border-left or style:border-line-width-left
        # ODT styles are split between named styles (styles.xml) and automatic styles (content.xml)
        
        # Find the style name used for the paragraph containing the new text
        # Regex to find <text:p text:style-name="P1">...tactile check...</text:p>
        # Note: XML namespaces make this tricky with pure regex, but we try robust patterns
        
        para_match = re.search(r'<text:p[^>]*text:style-name="([^"]+)"[^>]*>[^<]*tactile check', content_xml)
        if para_match:
            style_name = para_match.group(1)
            result["debug_info"].append(f"Target text uses style: {style_name}")
            
            # Look for this style definition in content.xml (automatic styles) or styles.xml
            # We look for border properties
            style_def_pattern = r'<style:style[^>]*style:name="' + re.escape(style_name) + r'"[^>]*>(.*?)</style:style>'
            
            style_content = ""
            match_content = re.search(style_def_pattern, content_xml, re.DOTALL)
            match_styles = re.search(style_def_pattern, styles_xml, re.DOTALL)
            
            if match_content: style_content += match_content.group(1)
            if match_styles: style_content += match_styles.group(1)
            
            # Check for left border
            if 'fo:border-left' in style_content or 'style:border-line-width-left' in style_content:
                 # Check it's not "none"
                 if 'none' not in style_content.split('border-left')[1].split('"')[0]:
                     result["revision_bar_found"] = True
            elif 'fo:border' in style_content and 'none' not in style_content:
                 # fo:border applies to all sides, which counts as a left border too
                 result["revision_bar_found"] = True
                 
        else:
             result["debug_info"].append("Could not find paragraph with target text")

        # 3. Check Warning Box (Border all sides + Bold)
        # Find paragraph with "WARNING"
        warn_match = re.search(r'<text:p[^>]*text:style-name="([^"]+)"[^>]*>[^<]*WARNING[^<]*</text:p>', content_xml)
        if warn_match:
            warn_style = warn_match.group(1)
            
            warn_def_pattern = r'<style:style[^>]*style:name="' + re.escape(warn_style) + r'"[^>]*>(.*?)</style:style>'
            warn_style_content = ""
            w_match_c = re.search(warn_def_pattern, content_xml, re.DOTALL)
            w_match_s = re.search(warn_def_pattern, styles_xml, re.DOTALL)
            
            if w_match_c: warn_style_content += w_match_c.group(1)
            if w_match_s: warn_style_content += w_match_s.group(1)
            
            # Check Borders
            if 'fo:border=' in warn_style_content or ('fo:border-top' in warn_style_content and 'fo:border-bottom' in warn_style_content):
                 if 'none' not in warn_style_content:
                     result["warning_box_found"] = True
            
            # Check Bold
            if 'fo:font-weight="bold"' in warn_style_content:
                result["warning_bold_found"] = True
        
        # 4. Check Header
        # Header text is usually in styles.xml under <style:header>
        if "Revision: 05" in styles_xml:
            result["header_updated"] = True

except Exception as e:
    result["error"] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)

PYEOF

# 5. Inject the timestamp check result into the JSON
# We use a temporary python snippet to merge the bash variable
python3 -c "import json; d=json.load(open('/tmp/task_result.json')); d['file_saved_during_task'] = $FILE_SAVED_DURING_TASK; json.dump(d, open('/tmp/task_result.json','w'))"

echo "Export complete. Result:"
cat /tmp/task_result.json