#!/bin/bash
echo "=== Exporting election_1860_swing_states_analysis task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final_state.png" 2>/dev/null || true

SCRIPT_FILE="/home/ga/Documents/analyze_1860.py"
HTML_FILE="/home/ga/Documents/swing_states_1860.html"
TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")

SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
SCRIPT_SIZE=0
SCRIPT_CONTENT=""

HTML_EXISTS="false"
HTML_MODIFIED="false"
HTML_SIZE=0

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat --format=%s "$SCRIPT_FILE" 2>/dev/null || echo "0")
    SCRIPT_MTIME=$(stat --format=%Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    # Safely base64 encode the script content to embed in JSON
    SCRIPT_CONTENT=$(base64 -w 0 "$SCRIPT_FILE" 2>/dev/null || echo "")
fi

if [ -f "$HTML_FILE" ]; then
    HTML_EXISTS="true"
    HTML_SIZE=$(stat --format=%s "$HTML_FILE" 2>/dev/null || echo "0")
    HTML_MTIME=$(stat --format=%Y "$HTML_FILE" 2>/dev/null || echo "0")
    if [ "$HTML_MTIME" -gt "$TASK_START" ]; then
        HTML_MODIFIED="true"
    fi
    
    # Parse the HTML file with a quick python script to extract states and check structure
    python3 << 'PYEOF' > /tmp/html_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/html_analysis.json
import json
import os
import re

result = {
    "has_table": False,
    "has_tr": False,
    "has_td": False,
    "text_content": "",
    "raw_html": "",
    "error": None
}

try:
    with open("/home/ga/Documents/swing_states_1860.html", "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
        
    result["raw_html"] = content[:5000] # store raw snippet
    
    # Strip HTML tags for clean text matching
    plain_text = re.sub(r'<[^>]+>', ' ', content)
    plain_text = re.sub(r'\s+', ' ', plain_text).strip()
    result["text_content"] = plain_text
    
    # Check for basic HTML table structure
    content_lower = content.lower()
    result["has_table"] = "<table" in content_lower
    result["has_tr"] = "<tr" in content_lower
    result["has_td"] = "<td" in content_lower

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
else:
    echo '{"has_table":false, "text_content":"", "error":"no_file"}' > /tmp/html_analysis.json
fi

# Combine everything into the final JSON output
TEMP_JSON=$(mktemp /tmp/election_result.XXXXXX.json)
python3 << PYEOF > "$TEMP_JSON"
import json
import base64

try:
    with open('/tmp/html_analysis.json', 'r') as f:
        html_analysis = json.load(f)
except Exception:
    html_analysis = {}

result = {
    "script_exists": ${SCRIPT_EXISTS},
    "script_modified": ${SCRIPT_MODIFIED},
    "script_size": ${SCRIPT_SIZE},
    "script_b64": "${SCRIPT_CONTENT}",
    "html_exists": ${HTML_EXISTS},
    "html_modified": ${HTML_MODIFIED},
    "html_size": ${HTML_SIZE},
    "html_analysis": html_analysis
}

print(json.dumps(result, indent=2))
PYEOF

chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/election_result.json
echo "Result saved to /tmp/election_result.json"
echo "=== Export complete ==="