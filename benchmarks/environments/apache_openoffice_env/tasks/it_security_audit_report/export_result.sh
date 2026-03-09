#!/bin/bash
echo "=== Exporting IT Security Audit Report Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

OUTPUT_PATH="/home/ga/Documents/Apex_Security_Report_Q1_2025.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file stats
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze ODT Content using Python
# We extract content.xml and styles.xml to verify content and styles
python3 << 'PYEOF'
import zipfile
import json
import re
import os
import sys

output_path = "/home/ga/Documents/Apex_Security_Report_Q1_2025.odt"
result_data = {
    "vulns_found": [],
    "headings_count": 0,
    "has_toc": False,
    "has_table": False,
    "header_found": False,
    "page_numbers_found": False,
    "color_coding": {
        "Critical": False,
        "High": False,
        "Medium": False,
        "Low": False
    },
    "styles_used": False
}

if not os.path.exists(output_path):
    print(json.dumps(result_data))
    with open("/tmp/odt_analysis.json", "w") as f:
        json.dump(result_data, f)
    sys.exit(0)

try:
    with zipfile.ZipFile(output_path, 'r') as zf:
        content_xml = zf.read('content.xml').decode('utf-8', errors='ignore')
        styles_xml = zf.read('styles.xml').decode('utf-8', errors='ignore')
        
        # 1. Check for Content (Vulnerability IDs)
        vulns = ["VULN-001", "VULN-002", "VULN-003", "VULN-004", "VULN-005"]
        for v in vulns:
            if v in content_xml:
                result_data["vulns_found"].append(v)
        
        # 2. Check for Structure
        result_data["headings_count"] = content_xml.count('<text:h')
        result_data["has_toc"] = 'text:table-of-content' in content_xml
        result_data["has_table"] = '<table:table' in content_xml
        
        # 3. Check for Header/Footer in styles.xml
        # Look for the confidential text in header definitions
        if "CONFIDENTIAL" in styles_xml or "CONFIDENTIAL" in content_xml:
            result_data["header_found"] = True
            
        if "text:page-number" in styles_xml or "text:page-number" in content_xml:
            result_data["page_numbers_found"] = True

        # 4. Check for Color Coding (Complex)
        # We need to map style names to colors first
        # Extract style definitions from both xmls
        style_color_map = {}
        
        # Regex to find style definitions and their text properties with color
        # Format: <style:style style:name="T1" ...><style:text-properties fo:color="#ff0000" .../></style:style>
        
        all_xml = content_xml + styles_xml
        
        # Find all styles and their colors
        # This is a heuristic regex, might miss complex inheritance but works for typical usage
        style_regex = r'<style:style[^>]*style:name="([^"]+)"[^>]*>.*?<style:text-properties[^>]*fo:color="([^"]+)"'
        matches = re.findall(style_regex, all_xml, re.DOTALL)
        for name, color in matches:
            style_color_map[name] = color.lower()

        # Helper to check if a specific severity word is wrapped in a colored style
        def check_severity_color(severity, valid_hex_prefixes):
            # Find occurrences of the severity word
            # Pattern: <text:span text:style-name="StyleName">Severity</text:span>
            # OR direct formatting auto-styles
            span_regex = r'<text:span text:style-name="([^"]+)">\s*' + severity + r'\s*</text:span>'
            span_matches = re.findall(span_regex, content_xml)
            
            for style_name in span_matches:
                if style_name in style_color_map:
                    color = style_color_map[style_name]
                    for prefix in valid_hex_prefixes:
                        if prefix in color:
                            return True
            return False

        # Check Critical (Red)
        result_data["color_coding"]["Critical"] = check_severity_color("Critical", ["#ff0000", "#cc0000", "#dd0000"])
        # Check High (Orange)
        result_data["color_coding"]["High"] = check_severity_color("High", ["#ff8000", "#ffa500", "#ff9900"])
        # Check Medium (Yellow/Gold)
        result_data["color_coding"]["Medium"] = check_severity_color("Medium", ["#ffff00", "#ffd700", "#ffcc00"])
        # Check Low (Green)
        result_data["color_coding"]["Low"] = check_severity_color("Low", ["#008000", "#00ff00", "#00cc00", "#006400"])

        # Check if custom styles were likely used (look for user-defined style names like "Risk-Critical")
        if "Risk-" in styles_xml or "Severity" in styles_xml:
            result_data["styles_used"] = True

except Exception as e:
    result_data["error"] = str(e)

with open("/tmp/odt_analysis.json", "w") as f:
    json.dump(result_data, f)
PYEOF

# 4. Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "odt_analysis": $(cat /tmp/odt_analysis.json)
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json