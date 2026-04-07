#!/bin/bash
echo "=== Exporting Gutenberg Readability result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Capture final state
su - ga -c "$SUGAR_ENV scrot /tmp/readability_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/readability_start_ts 2>/dev/null || echo "0")
SCRIPT_MTIME=$(stat -c %Y /home/ga/Documents/ari_calculator.py 2>/dev/null || echo "0")
ODT_MTIME=$(stat -c %Y /home/ga/Documents/alice_review.odt 2>/dev/null || echo "0")

SCRIPT_MODIFIED="false"
if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
    SCRIPT_MODIFIED="true"
fi

ODT_MODIFIED="false"
if [ "$ODT_MTIME" -gt "$TASK_START" ]; then
    ODT_MODIFIED="true"
fi

# Run python parser to examine files
python3 << 'EOF' > /tmp/readability_parsed.json
import json
import zipfile
import re
import os

result = {
    "script_exists": False,
    "script_mentions_file": False,
    "script_has_constants": False,
    "odt_exists": False,
    "has_heading": False,
    "has_title": False,
    "reported_words": None,
    "reported_sentences": None,
    "reported_ari": None,
    "error": None,
    "plain_text_preview": ""
}

script_path = "/home/ga/Documents/ari_calculator.py"
if os.path.exists(script_path):
    result["script_exists"] = True
    try:
        with open(script_path, "r", encoding="utf-8") as f:
            content = f.read()
            if "alice" in content.lower():
                result["script_mentions_file"] = True
            if "4.71" in content and "21.43" in content:
                result["script_has_constants"] = True
    except Exception as e:
        result["error"] = str(e)

odt_path = "/home/ga/Documents/alice_review.odt"
if os.path.exists(odt_path):
    result["odt_exists"] = True
    try:
        with zipfile.ZipFile(odt_path, 'r') as z:
            with z.open('content.xml') as f:
                content = f.read().decode('utf-8', errors='ignore')
        
        # Parse basic plain text out of ODT xml
        plain_text = re.sub(r'<[^>]+>', ' ', content)
        plain_text = plain_text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
        
        result["plain_text_preview"] = plain_text[:500]
        
        # Check headings and titles using regex
        if re.search(r'(?i)Literary\s+Text\s+Readability\s+Assessment', plain_text):
            result["has_heading"] = True
            
        if re.search(r"(?i)Alice['’]?s\s+Adventures\s+in\s+Wonderland", plain_text):
            result["has_title"] = True
            
        # Tolerant extraction of numerical metrics
        words_match = re.search(r'(?i)\bwords?[^\d]*([\d,\.]+)', plain_text)
        if words_match:
            try:
                val = words_match.group(1).replace(',', '')
                if val.endswith('.'): val = val[:-1]
                result["reported_words"] = float(val)
            except:
                pass
            
        sentences_match = re.search(r'(?i)\bsentences?[^\d]*([\d,\.]+)', plain_text)
        if sentences_match:
            try:
                val = sentences_match.group(1).replace(',', '')
                if val.endswith('.'): val = val[:-1]
                result["reported_sentences"] = float(val)
            except:
                pass
            
        ari_match = re.search(r'(?i)\bari[^\d]*([\d,\.]+)', plain_text)
        if ari_match:
            try:
                val = ari_match.group(1).replace(',', '')
                if val.endswith('.'): val = val[:-1]
                result["reported_ari"] = float(val)
            except:
                pass
            
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
EOF

# Merge bash booleans with parsed JSON
python3 << EOF > /tmp/readability_result.json
import json
with open('/tmp/readability_parsed.json', 'r') as f:
    data = json.load(f)

data["script_modified"] = "$SCRIPT_MODIFIED" == "true"
data["odt_modified"] = "$ODT_MODIFIED" == "true"

with open('/tmp/readability_result.json', 'w') as f:
    json.dump(data, f)
EOF

chmod 666 /tmp/readability_result.json
echo "Result saved to /tmp/readability_result.json"
cat /tmp/readability_result.json
echo "=== Export complete ==="