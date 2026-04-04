#!/bin/bash
# Export script for Post-Incident Review Creation task
echo "=== Exporting PIR Task Result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/INC-4092_PIR.odt"
RESULT_JSON="/tmp/task_result.json"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Analyze the ODT file using Python
# We extract the content.xml and styles.xml to verify structure, tables, and formatting.
python3 << 'PYEOF'
import zipfile
import json
import os
import re

output_path = "/home/ga/Documents/INC-4092_PIR.odt"
result = {
    "file_exists": False,
    "headings_found": [],
    "heading1_count": 0,
    "title_centered": False,
    "table_count": 0,
    "courier_usage_count": 0,
    "footer_text_found": False,
    "page_numbers_found": False,
    "content_snippets": [],
    "file_size": 0
}

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    
    try:
        with zipfile.ZipFile(output_path, 'r') as zf:
            # --- Analyze content.xml ---
            content_xml = zf.read('content.xml').decode('utf-8', errors='ignore')
            
            # Check Headings (Heading 1 style)
            # Regex looks for text:h with outline-level 1
            h1_matches = re.findall(r'<text:h[^>]*text:outline-level="1"[^>]*>(.*?)</text:h>', content_xml)
            result["heading1_count"] = len(h1_matches)
            # Clean tags from headings to get raw text
            result["headings_found"] = [re.sub(r'<[^>]+>', '', h) for h in h1_matches]
            
            # Check Title Centering
            # Look for the title text and check if its style has center alignment
            # This is complex in ODT; we'll check if "Post-Incident Review" is in a paragraph
            # and later verify if that style has text-align="center" in automatic-styles
            # For simplicity in this script, we'll check for the title string existence first.
            if "Post-Incident Review: INC-4092" in re.sub(r'<[^>]+>', '', content_xml):
                 # Weak check for centering: often implies a specific style. 
                 # We will defer strict style parsing to complex logic or rely on verify_pir_creation logic.
                 # Here we just capture if the text exists in a Heading 1
                 pass

            # Check Tables
            result["table_count"] = content_xml.count('<table:table ')

            # Check Courier New usage
            # Look for style definitions or usage.
            # ODT often defines an automatic style for the font, then references it.
            # We look for style-name references on spans containing the technical terms.
            # Simpler proxy: Check if "Courier New" or "Courier" appears in font-face-decls 
            # AND if the technical terms are present in the text.
            technical_terms = ["SQLSTATE 40P01", "inventory_items"]
            terms_present = all(term in content_xml for term in technical_terms)
            
            # Check styles.xml/content.xml for font declarations
            font_courier = "Courier" in content_xml or "Mono" in content_xml
            if terms_present and font_courier:
                result["courier_usage_count"] = 1 # simplified indicator

            # --- Analyze styles.xml (Footers) ---
            styles_xml = ""
            if 'styles.xml' in zf.namelist():
                styles_xml = zf.read('styles.xml').decode('utf-8', errors='ignore')
            
            # Check Footer Content
            # Footers are often defined in master-page > footer > text
            full_xml = content_xml + styles_xml
            if "OmniCart Confidential" in full_xml:
                result["footer_text_found"] = True
            
            if "text:page-number" in full_xml:
                result["page_numbers_found"] = True

            # Extract some raw text for context checking
            plain_text = re.sub(r'<[^>]+>', ' ', content_xml)
            result["content_snippets"] = plain_text[:500] # First 500 chars

    except Exception as e:
        result["error"] = str(e)

# Write result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# 3. Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="