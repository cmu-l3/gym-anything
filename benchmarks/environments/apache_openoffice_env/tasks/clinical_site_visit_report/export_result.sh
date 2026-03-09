#!/bin/bash
echo "=== Exporting Clinical Site Visit Report Result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_PATH="/home/ga/Documents/IMV_Report_Site_142.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TIMESTAMP=$(date -Iseconds)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check basic file attributes
if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    
    # Check if modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# 3. Python script to analyze ODT content (Styles, Content, Logic)
# We extract content.xml and styles.xml from the ODT zip and parse them.
python3 << 'PYEOF'
import zipfile
import re
import json
import sys

output_path = "/home/ga/Documents/IMV_Report_Site_142.odt"
result = {
    "has_protocol_header": False,
    "heading1_count": 0,
    "has_enrollment_table": False,
    "calculated_active_correct": False,
    "has_action_items_table": False,
    "conditional_formatting_found": False,
    "page_numbers_found": False
}

try:
    if not os.path.exists(output_path):
        raise FileNotFoundError("File not found")

    with zipfile.ZipFile(output_path, 'r') as z:
        # Read content.xml (Body text)
        content_xml = z.read('content.xml').decode('utf-8')
        
        # Read styles.xml (Headers/Footers)
        styles_xml = ""
        if 'styles.xml' in z.namelist():
            styles_xml = z.read('styles.xml').decode('utf-8')

        # --- Check 1: Headers (Protocol ZN-994 / Site 142) ---
        # Headers are usually in styles.xml or defined in master-styles
        header_text_search = (content_xml + styles_xml).lower()
        if "zn-994" in header_text_search and "142" in header_text_search:
            result["has_protocol_header"] = True

        # --- Check 2: Heading 1 Styles ---
        # Look for <text:h text:style-name="Heading_20_1" ...> or outline-level="1"
        # The specific style name might vary, but outline-level="1" is standard for ODT
        h1_matches = re.findall(r'text:outline-level="1"', content_xml)
        result["heading1_count"] = len(h1_matches)

        # --- Check 3: Logic Check (Active = 9) ---
        # We look for the number 9 in a table cell or paragraph near "Active"
        # Simplistic check: is "9" present?
        # Robust check: "Active" and "9" appear in close proximity (e.g. within 200 chars)
        active_indices = [m.start() for m in re.finditer(r'Active', content_xml)]
        for idx in active_indices:
            window = content_xml[idx:idx+300]
            if ">9<" in window or ">9 <" in window: # Number inside XML tags
                result["calculated_active_correct"] = True
                break

        # --- Check 4: Tables ---
        # Count <table:table>
        tables = re.findall(r'<table:table ', content_xml)
        if len(tables) >= 2:
            result["has_enrollment_table"] = True
            result["has_action_items_table"] = True
        elif len(tables) == 1:
            result["has_enrollment_table"] = True # Partial credit assumption

        # --- Check 5: Conditional Formatting on "Open" ---
        # Strategy: Find "Open" text nodes. Check their parent style.
        # Then find that style definition and check for color (#ff0000) or background color (yellow).
        
        # 1. Find style names used for "Open"
        # Pattern: <text:span text:style-name="T1">Open</text:span>
        open_spans = re.findall(r'<text:span text:style-name="([^"]+)">\s*Open\s*</text:span>', content_xml)
        
        # 2. Also check automatic styles in content.xml
        style_defs = re.findall(r'<style:style style:name="([^"]+)" style:family="text">.*?</style:style>', content_xml, re.DOTALL)
        
        for style_name in open_spans:
            # Find definition for this style
            for definition in style_defs:
                if f'style:name="{style_name}"' in definition:
                    # Check for Red Text (fo:color="#ff0000" or similar)
                    if 'fo:color="#ff0000"' in definition or 'fo:color="#FF0000"' in definition:
                        result["conditional_formatting_found"] = True
                    # Check for Highlight (fo:background-color="#ffff00" or similar)
                    if 'fo:background-color="#ffff00"' in definition or 'fo:background-color="#FFFF00"' in definition:
                        result["conditional_formatting_found"] = True
        
        # --- Check 6: Page Numbers ---
        # Look for <text:page-number> field
        if "<text:page-number" in content_xml or "<text:page-number" in styles_xml:
            result["page_numbers_found"] = True

except Exception as e:
    result["error"] = str(e)

# Save analysis to file
with open('/tmp/odt_analysis.json', 'w') as f:
    json.dump(result, f)
PYEOF

# 4. Create final JSON result
ANALYSIS=$(cat /tmp/odt_analysis.json 2>/dev/null || echo "{}")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $CREATED_DURING_TASK,
    "analysis": $ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="