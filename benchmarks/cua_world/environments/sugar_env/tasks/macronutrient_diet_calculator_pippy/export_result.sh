#!/bin/bash
echo "=== Exporting macronutrient_diet_calculator_pippy task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/diet_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/diet_calculator_start_ts 2>/dev/null || echo "0")
SCRIPT_FILE="/home/ga/Documents/nutrition_calculator.py"
REPORT_FILE="/home/ga/Documents/diet_report.txt"
JOURNAL_DIR="/home/ga/.sugar/default/datastore"

# Variables to collect
SCRIPT_EXISTS="false"
SCRIPT_SIZE=0
SCRIPT_MODIFIED="false"
HAS_CSV_REFERENCE="false"

REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MODIFIED="false"

JOURNAL_TITLE_FOUND="false"

# 1. Check Python Script
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat --format=%s "$SCRIPT_FILE" 2>/dev/null || echo "0")
    SCRIPT_MTIME=$(stat --format=%Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    if grep -q "nutrition.csv" "$SCRIPT_FILE" 2>/dev/null; then
        HAS_CSV_REFERENCE="true"
    fi
fi

# 2. Check Text Report
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat --format=%s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat --format=%Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED="true"
    fi
fi

# 3. Parse Text Report for values using Python
python3 << 'PYEOF' > /tmp/diet_report_parsed.json 2>/dev/null || echo '{"error": "parse_failed"}' > /tmp/diet_report_parsed.json
import re
import json
import os

result = {
    "parsed_calories": None,
    "parsed_protein": None,
    "parsed_carbs": None,
    "parsed_fat": None,
    "error": None
}

report_path = "/home/ga/Documents/diet_report.txt"
if os.path.exists(report_path):
    try:
        with open(report_path, 'r') as f:
            lines = f.readlines()
            
        for line in lines:
            line_lower = line.lower()
            # Find all numbers (integers or decimals) in the line
            nums = re.findall(r'\b\d+(?:\.\d+)?\b', line)
            if not nums:
                continue
            
            # Assume the last number on the line is the total value
            val = float(nums[-1])
            
            if 'cal' in line_lower:
                result["parsed_calories"] = val
            elif 'pro' in line_lower:
                result["parsed_protein"] = val
            elif 'carb' in line_lower:
                result["parsed_carbs"] = val
            elif 'fat' in line_lower:
                result["parsed_fat"] = val
    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "file_not_found"

print(json.dumps(result))
PYEOF

# 4. Check Sugar Journal
if [ -d "$JOURNAL_DIR" ]; then
    # Look for title files containing "Diet Calculator"
    MATCH=$(find "$JOURNAL_DIR" -name "title" -exec grep -il "Diet Calculator" {} \; 2>/dev/null | head -1)
    if [ -n "$MATCH" ]; then
        JOURNAL_TITLE_FOUND="true"
    fi
fi

# Read parsed values
PARSED_CALORIES=$(python3 -c "import json; print(json.load(open('/tmp/diet_report_parsed.json')).get('parsed_calories') or 'null')" 2>/dev/null || echo "null")
PARSED_PROTEIN=$(python3 -c "import json; print(json.load(open('/tmp/diet_report_parsed.json')).get('parsed_protein') or 'null')" 2>/dev/null || echo "null")
PARSED_CARBS=$(python3 -c "import json; print(json.load(open('/tmp/diet_report_parsed.json')).get('parsed_carbs') or 'null')" 2>/dev/null || echo "null")
PARSED_FAT=$(python3 -c "import json; print(json.load(open('/tmp/diet_report_parsed.json')).get('parsed_fat') or 'null')" 2>/dev/null || echo "null")

# Combine into final result JSON
cat > /tmp/macronutrient_diet_calculator_result.json << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "script_modified": $SCRIPT_MODIFIED,
    "script_size": $SCRIPT_SIZE,
    "has_csv_reference": $HAS_CSV_REFERENCE,
    "report_exists": $REPORT_EXISTS,
    "report_modified": $REPORT_MODIFIED,
    "report_size": $REPORT_SIZE,
    "parsed_calories": $PARSED_CALORIES,
    "parsed_protein": $PARSED_PROTEIN,
    "parsed_carbs": $PARSED_CARBS,
    "parsed_fat": $PARSED_FAT,
    "journal_title_found": $JOURNAL_TITLE_FOUND
}
EOF

chmod 666 /tmp/macronutrient_diet_calculator_result.json
echo "Result saved to /tmp/macronutrient_diet_calculator_result.json"
cat /tmp/macronutrient_diet_calculator_result.json
echo "=== Export complete ==="