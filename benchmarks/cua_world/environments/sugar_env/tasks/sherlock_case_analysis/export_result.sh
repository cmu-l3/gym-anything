#!/bin/bash
echo "=== Exporting sherlock_case_analysis task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Capture final state screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/sherlock_task_end.png" 2>/dev/null || true

ODT_FILE="/home/ga/Documents/case_analysis.odt"
TASK_START=$(cat /tmp/sherlock_case_analysis_start_ts 2>/dev/null || echo "0")

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
    
    # Parse ODT (ZIP structure containing content.xml) using Python
    python3 << 'PYEOF' > /tmp/sherlock_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/sherlock_analysis.json
import json
import zipfile
import re

result = {
    "has_summary": False,
    "has_characters": False,
    "has_clues": False,
    "has_conclusion": False,
    "mentions_holmes": False,
    "mentions_watson": False,
    "mentions_adler": False,
    "mentions_king": False,
    "mentions_photograph": False,
    "mentions_disguise": False,
    "mentions_briony": False,
    "text_length": 0,
    "error": None
}

odt_file = "/home/ga/Documents/case_analysis.odt"

try:
    with zipfile.ZipFile(odt_file, 'r') as z:
        if 'content.xml' in z.namelist():
            with z.open('content.xml') as f:
                content = f.read().decode('utf-8')
                
            # Strip XML to get clean readable text
            plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
            plain_text = plain_text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
            
            result["text_length"] = len(plain_text.strip())
            
            # Check for required headings
            result["has_summary"] = bool(re.search(r'case\s+summary', plain_text))
            result["has_characters"] = bool(re.search(r'characters', plain_text))
            result["has_clues"] = bool(re.search(r'clues\s+(and|&)\s+deductions', plain_text))
            result["has_conclusion"] = bool(re.search(r'conclusion', plain_text))
            
            # Check for specific characters and plot elements
            result["mentions_holmes"] = bool(re.search(r'holmes', plain_text))
            result["mentions_watson"] = bool(re.search(r'watson', plain_text))
            result["mentions_adler"] = bool(re.search(r'adler|irene', plain_text))
            result["mentions_king"] = bool(re.search(r'king|bohemia', plain_text))
            result["mentions_photograph"] = bool(re.search(r'photograph|photo', plain_text))
            result["mentions_disguise"] = bool(re.search(r'disguise|clergyman|groom', plain_text))
            result["mentions_briony"] = bool(re.search(r'briony\s+lodge', plain_text))
            
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
fi

# Combine generic file stats with Python content analysis output
if [ -f /tmp/sherlock_analysis.json ]; then
    ANALYSIS_JSON=$(cat /tmp/sherlock_analysis.json)
else
    ANALYSIS_JSON="{}"
fi

cat > /tmp/sherlock_case_analysis_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "analysis": $ANALYSIS_JSON
}
EOF

chmod 666 /tmp/sherlock_case_analysis_result.json
echo "Result saved to /tmp/sherlock_case_analysis_result.json"
echo "=== Export complete ==="