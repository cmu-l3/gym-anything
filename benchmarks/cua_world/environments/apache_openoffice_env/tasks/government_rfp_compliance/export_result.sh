#!/bin/bash
echo "=== Exporting RFP Compliance Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define output file
OUTPUT_FILE="/home/ga/Documents/TechFlow_Proposal_Volume_I.odt"

# 3. Analyze ODT file using Python
# We inspect styles.xml for page layout (margins, header/footer) and content.xml for headings
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys

output_path = "/home/ga/Documents/TechFlow_Proposal_Volume_I.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "margins_correct": False,
    "margins_details": {},
    "header_text_found": False,
    "footer_page_number_found": False,
    "heading1_count": 0,
    "content_found": False,
    "parse_error": None
}

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    
    try:
        with zipfile.ZipFile(output_path, 'r') as zf:
            # 1. Check Styles (Margins, Header, Footer)
            styles_xml = zf.read('styles.xml').decode('utf-8', errors='ignore')
            
            # Parsing Page Layout
            # Look for <style:page-layout-properties ...>
            # We expect fo:margin-top="1in" or "2.54cm", etc.
            # Note: ODT might store them as "0.999in" or "2.539cm" due to precision
            
            # Simple Regex check for the standard page layout
            # Warning: There might be multiple page layouts. We usually check the default or the one used.
            
            margins = {}
            for side in ['top', 'bottom', 'left', 'right']:
                pattern = f'fo:margin-{side}="([^"]+)"'
                matches = re.findall(pattern, styles_xml)
                margins[side] = matches
            
            result["margins_details"] = margins
            
            # Check for compliance (approx 1in or 2.54cm)
            # We check if ANY found margin matches the requirement, as documents can have multiple styles
            valid_margin = False
            compliant_sides = 0
            for side in ['top', 'bottom', 'left', 'right']:
                vals = margins.get(side, [])
                side_valid = False
                for v in vals:
                    # Clean value (remove units)
                    if 'in' in v:
                        num = float(v.replace('in', ''))
                        if 0.95 <= num <= 1.05: side_valid = True
                    elif 'cm' in v:
                        num = float(v.replace('cm', ''))
                        if 2.4 <= num <= 2.6: side_valid = True
                if side_valid:
                    compliant_sides += 1
            
            if compliant_sides >= 4:
                result["margins_correct"] = True

            # 2. Check Header content
            # Headers are often defined in styles.xml under <style:header>
            # But the TEXT content of the header is usually in styles.xml (if simple) or content.xml?
            # In ODT, header content is often in styles.xml inside <style:master-page> -> <style:header>
            
            # Search for the specific header text in styles.xml (headers are part of page styles)
            header_text = "RFP #2026-WIFI-09"
            if header_text in styles_xml:
                result["header_text_found"] = True
            
            # 3. Check Footer Page Number
            # Look for <text:page-number> inside styles.xml (usually in footer)
            if "<text:page-number" in styles_xml:
                result["footer_page_number_found"] = True
                
            # 4. Check Content (Headings and Body)
            content_xml = zf.read('content.xml').decode('utf-8', errors='ignore')
            
            # Check for Heading 1 usage
            # <text:h text:style-name="Heading_20_1" text:outline-level="1">
            heading_matches = re.findall(r'<text:h[^>]*text:outline-level="1"[^>]*>', content_xml)
            result["heading1_count"] = len(heading_matches)
            
            # Check for content keywords
            if "TechFlow Solutions" in content_xml and "Municipal" in content_xml:
                result["content_found"] = True

    except Exception as e:
        result["parse_error"] = str(e)

# Save result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# 4. Handle permission/move
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export completed. Result:"
cat /tmp/task_result.json