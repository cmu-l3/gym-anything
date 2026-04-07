#!/bin/bash
echo "=== Exporting investment_growth_worksheet task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/investment_task_end.png" 2>/dev/null || true

ODT_FILE="/home/ga/Documents/investment_growth.odt"
TASK_START=$(cat /tmp/investment_task_start_ts 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"

if [ -f "$ODT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$ODT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$ODT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    echo "Found: $ODT_FILE ($FILE_SIZE bytes)"

    # Create Python script to parse the ODT document
    cat << 'PYEOF' > /tmp/investment_analysis.py
import json
import zipfile
import re

result = {
    "has_formulas_section": False,
    "has_simple_formula": False,
    "has_compound_formula": False,
    "has_table": False,
    "has_analysis_section": False,
    "analysis_words": 0,
    "simple_vals_found": [],
    "compound_vals_found": [],
    "error": None
}

odt_file = "/home/ga/Documents/investment_growth.odt"

try:
    with zipfile.ZipFile(odt_file, 'r') as z:
        if 'content.xml' in z.namelist():
            content = z.read('content.xml').decode('utf-8')
        else:
            content = ""

    # Strip XML tags to get plain text
    plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
    plain_text = plain_text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')

    # Check for table element in XML structure
    result["has_table"] = 'table:table' in content or '<table' in content.lower()
    
    # Check for section headings
    result["has_formulas_section"] = bool(re.search(r'formulas?', plain_text))
    result["has_analysis_section"] = bool(re.search(r'analysis', plain_text))
    
    # Check for formula patterns (allowing flexible formatting)
    result["has_simple_formula"] = bool(re.search(r'p\s*\**\s*\(\s*1\s*\+\s*r\s*\**\s*t\s*\)', plain_text)) or bool(re.search(r'1\s*\+\s*r\s*\**\s*t', plain_text))
    result["has_compound_formula"] = bool(re.search(r'\(\s*1\s*\+\s*r\s*\)\s*\^?\s*t', plain_text))

    # Check for simple interest values (1050, 1100, 1150, 1200, 1250)
    simple_targets = ["1050", "1100", "1150", "1200", "1250"]
    result["simple_vals_found"] = [val for val in simple_targets if re.search(r'\b' + val + r'\b', plain_text)]
    
    # Check for compound interest values (Years 2-5 since Year 1 is identical)
    compound_targets = ["1102", "1157", "1215", "1276"]
    result["compound_vals_found"] = [val for val in compound_targets if re.search(r'\b' + val + r'\b', plain_text)]

    # Word count estimation for the Analysis section
    analysis_split = re.split(r'\banalysis\b', plain_text, maxsplit=1)
    if len(analysis_split) > 1:
        result["analysis_words"] = len(analysis_split[1].split())

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    python3 /tmp/investment_analysis.py > /tmp/investment_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/investment_analysis.json
else:
    echo '{"error":"file_not_found"}' > /tmp/investment_analysis.json
fi

cat > /tmp/investment_growth_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "analysis": $(cat /tmp/investment_analysis.json)
}
EOF

chmod 666 /tmp/investment_growth_result.json
echo "Result saved to /tmp/investment_growth_result.json"
echo "=== Export complete ==="