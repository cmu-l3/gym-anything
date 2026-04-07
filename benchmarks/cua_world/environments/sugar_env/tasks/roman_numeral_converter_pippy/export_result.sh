#!/bin/bash
echo "=== Exporting roman_numeral_converter_pippy task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/pippy_task_end.png" 2>/dev/null || true

# We will use Python to parse the generated files and extract metrics
python3 << 'PYEOF' > /tmp/roman_analysis.json 2>/dev/null || echo '{"error":"export_script_failed"}' > /tmp/roman_analysis.json
import json
import os
import re

result = {
    "txt_exists": False,
    "html_exists": False,
    "txt_modified": False,
    "html_modified": False,
    "txt_size": 0,
    "html_size": 0,
    "txt_lines": 0,
    "txt_map": {},
    "html_has_table": False,
    "html_has_xlii": False,
    "error": None
}

txt_path = "/home/ga/Documents/roman_numerals.txt"
html_path = "/home/ga/Documents/roman_numerals.html"

try:
    with open("/tmp/roman_numeral_start_ts", "r") as f:
        start_ts = int(f.read().strip())
except Exception:
    start_ts = 0

try:
    if os.path.exists(txt_path):
        result["txt_exists"] = True
        result["txt_size"] = os.path.getsize(txt_path)
        if os.path.getmtime(txt_path) >= start_ts:
            result["txt_modified"] = True
        
        with open(txt_path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
            result["txt_lines"] = len([l for l in lines if l.strip()])
            
            # Parse N = ROMAN mappings
            # Looks for a number, optionally spaces, equals sign, optionally spaces, then roman numeral letters
            for line in lines:
                m = re.search(r'\b(\d+)\s*=\s*([ivxlcdmIVXLCDM]+)\b', line)
                if m:
                    num = str(int(m.group(1)))
                    roman = m.group(2).upper()
                    result["txt_map"][num] = roman

    if os.path.exists(html_path):
        result["html_exists"] = True
        result["html_size"] = os.path.getsize(html_path)
        if os.path.getmtime(html_path) >= start_ts:
            result["html_modified"] = True
            
        with open(html_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read().upper()
            if "<TABLE" in content:
                result["html_has_table"] = True
            # Check for a specific mid-range conversion inside the HTML to ensure content wasn't trivially faked
            if "XLII" in content:
                result["html_has_xlii"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Ensure safe file permissions for the verifier to read
chmod 666 /tmp/roman_analysis.json 2>/dev/null || true

echo "Result JSON saved to /tmp/roman_analysis.json"
cat /tmp/roman_analysis.json
echo ""
echo "=== Export complete ==="