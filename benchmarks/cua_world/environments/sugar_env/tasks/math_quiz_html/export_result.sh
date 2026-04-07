#!/bin/bash
echo "=== Exporting math_quiz_html task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/math_quiz_end.png" 2>/dev/null || true

HTML_FILE="/home/ga/Documents/math_quiz.html"
TASK_START=$(cat /tmp/math_quiz_start_ts 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"

if [ -f "$HTML_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$HTML_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$HTML_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    echo "Found: $HTML_FILE ($FILE_SIZE bytes, mtime=$FILE_MTIME)"

    # Parse HTML using Python
    python3 << 'PYEOF' > /tmp/math_quiz_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/math_quiz_analysis.json
import json
import re
import os

result = {
    "is_valid_html": False,
    "has_title": False,
    "has_script": False,
    "has_style": False,
    "input_count": 0,
    "has_button": False,
    "has_56": False,
    "has_144": False,
    "has_195": False,
    "has_256": False,
    "has_27": False,
    "has_js_logic": False,
    "has_score_text": False,
    "error": None
}

try:
    with open("/home/ga/Documents/math_quiz.html", "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    lower_content = content.lower()

    # Structure checks
    result["is_valid_html"] = "<html" in lower_content or "<!doctype" in lower_content
    result["has_title"] = "4th grade math challenge" in lower_content
    result["has_script"] = "<script" in lower_content
    result["has_style"] = "<style" in lower_content
    
    # Count inputs
    result["input_count"] = lower_content.count("<input")
    
    # Button checks
    result["has_button"] = "<button" in lower_content or "type=\"submit\"" in lower_content or "type='submit'" in lower_content or "type=\"button\"" in lower_content or "type='button'" in lower_content

    # Values check
    result["has_56"] = bool(re.search(r'\b56\b', content))
    result["has_144"] = bool(re.search(r'\b144\b', content))
    result["has_195"] = bool(re.search(r'\b195\b', content))
    result["has_256"] = bool(re.search(r'\b256\b', content))
    result["has_27"] = bool(re.search(r'\b27\b', content))

    # JavaScript logic check (look for == or ===)
    result["has_js_logic"] = "==" in content or "===" in content

    # Score text feedback check
    result["has_score_text"] = bool(re.search(r'\b(out of|score|correct)\b', lower_content))

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    # Evaluate variables from JSON
    if [ -f /tmp/math_quiz_analysis.json ]; then
        IS_VALID_HTML=$(python3 -c "import json; d=json.load(open('/tmp/math_quiz_analysis.json')); print(str(d.get('is_valid_html',False)).lower())" 2>/dev/null || echo "false")
        HAS_TITLE=$(python3 -c "import json; d=json.load(open('/tmp/math_quiz_analysis.json')); print(str(d.get('has_title',False)).lower())" 2>/dev/null || echo "false")
        HAS_SCRIPT=$(python3 -c "import json; d=json.load(open('/tmp/math_quiz_analysis.json')); print(str(d.get('has_script',False)).lower())" 2>/dev/null || echo "false")
        HAS_STYLE=$(python3 -c "import json; d=json.load(open('/tmp/math_quiz_analysis.json')); print(str(d.get('has_style',False)).lower())" 2>/dev/null || echo "false")
        INPUT_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/math_quiz_analysis.json')); print(d.get('input_count',0))" 2>/dev/null || echo "0")
        HAS_BUTTON=$(python3 -c "import json; d=json.load(open('/tmp/math_quiz_analysis.json')); print(str(d.get('has_button',False)).lower())" 2>/dev/null || echo "false")
        HAS_56=$(python3 -c "import json; d=json.load(open('/tmp/math_quiz_analysis.json')); print(str(d.get('has_56',False)).lower())" 2>/dev/null || echo "false")
        HAS_144=$(python3 -c "import json; d=json.load(open('/tmp/math_quiz_analysis.json')); print(str(d.get('has_144',False)).lower())" 2>/dev/null || echo "false")
        HAS_195=$(python3 -c "import json; d=json.load(open('/tmp/math_quiz_analysis.json')); print(str(d.get('has_195',False)).lower())" 2>/dev/null || echo "false")
        HAS_256=$(python3 -c "import json; d=json.load(open('/tmp/math_quiz_analysis.json')); print(str(d.get('has_256',False)).lower())" 2>/dev/null || echo "false")
        HAS_27=$(python3 -c "import json; d=json.load(open('/tmp/math_quiz_analysis.json')); print(str(d.get('has_27',False)).lower())" 2>/dev/null || echo "false")
        HAS_JS_LOGIC=$(python3 -c "import json; d=json.load(open('/tmp/math_quiz_analysis.json')); print(str(d.get('has_js_logic',False)).lower())" 2>/dev/null || echo "false")
        HAS_SCORE_TEXT=$(python3 -c "import json; d=json.load(open('/tmp/math_quiz_analysis.json')); print(str(d.get('has_score_text',False)).lower())" 2>/dev/null || echo "false")
    fi
else
    IS_VALID_HTML="false"
    HAS_TITLE="false"
    HAS_SCRIPT="false"
    HAS_STYLE="false"
    INPUT_COUNT=0
    HAS_BUTTON="false"
    HAS_56="false"
    HAS_144="false"
    HAS_195="false"
    HAS_256="false"
    HAS_27="false"
    HAS_JS_LOGIC="false"
    HAS_SCORE_TEXT="false"
fi

cat > /tmp/math_quiz_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "is_valid_html": $IS_VALID_HTML,
    "has_title": $HAS_TITLE,
    "has_script": $HAS_SCRIPT,
    "has_style": $HAS_STYLE,
    "input_count": $INPUT_COUNT,
    "has_button": $HAS_BUTTON,
    "has_56": $HAS_56,
    "has_144": $HAS_144,
    "has_195": $HAS_195,
    "has_256": $HAS_256,
    "has_27": $HAS_27,
    "has_js_logic": $HAS_JS_LOGIC,
    "has_score_text": $HAS_SCORE_TEXT
}
EOF

chmod 666 /tmp/math_quiz_result.json
echo "Result saved to /tmp/math_quiz_result.json"
cat /tmp/math_quiz_result.json
echo "=== Export complete ==="