#!/bin/bash
# Do NOT use set -e
echo "=== Exporting gapminder_demographics_worksheet task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

# Run Python parsing script to evaluate files dynamically
python3 << 'PYEOF' > /tmp/gapminder_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/gapminder_analysis.json
import json
import zipfile
import re
import os

result = {
    "odt_exists": False,
    "odt_size": 0,
    "odt_modified": False,
    "json_downloaded": False,
    "has_lesson_overview": False,
    "has_data_table_heading": False,
    "has_student_questions": False,
    "has_table_element": False,
    "rwanda_found": [],
    "afghanistan_found": [],
    "japan_found": [],
    "text_preview": "",
    "error": None
}

json_file = "/home/ga/Documents/gapminder.json"
if os.path.exists(json_file) and os.path.getsize(json_file) > 1000:
    result["json_downloaded"] = True

odt_file = "/home/ga/Documents/demographics_worksheet.odt"
if os.path.exists(odt_file):
    result["odt_exists"] = True
    result["odt_size"] = os.path.getsize(odt_file)
    
    try:
        mtime = os.path.getmtime(odt_file)
        with open('/tmp/task_start_time.txt', 'r') as f:
            start_time = float(f.read().strip())
        if mtime > start_time:
            result["odt_modified"] = True
    except Exception:
        pass

    try:
        with zipfile.ZipFile(odt_file, 'r') as z:
            with z.open('content.xml') as f:
                content = f.read().decode('utf-8')
        
        # Determine presence of actual ODT table
        result["has_table_element"] = 'table:table' in content or '<table' in content.lower()
        
        # Strip XML to plain text for keyword/value searching
        plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
        plain_text = plain_text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
        
        result["text_preview"] = plain_text[:500]
        
        result["has_lesson_overview"] = bool(re.search(r'lesson\s+overview', plain_text))
        result["has_data_table_heading"] = bool(re.search(r'data\s+table', plain_text))
        result["has_student_questions"] = bool(re.search(r'student\s+questions', plain_text))
        
        # Ground truth values for 1955 and 2005 (life_expect, fertility)
        gt = {
            "rwanda": ["41.5", "8", "46.242", "5.416"],
            "afghanistan": ["30.332", "7.671", "43.828", "7.196"],
            "japan": ["65.5", "2.08", "82.603", "1.27"]
        }
        
        def check_val(v, text):
            if v == "8":
                return bool(re.search(r'\b8(?:\.0*)?\b', text))
            else:
                pat1 = r'\b' + re.escape(v) + r'\b'
                pat2 = r'\b' + re.escape(v.replace('.', ',')) + r'\b'
                return bool(re.search(pat1, text)) or bool(re.search(pat2, text))
                
        for val in gt["rwanda"]:
            if check_val(val, plain_text):
                result["rwanda_found"].append(val)
                
        for val in gt["afghanistan"]:
            if check_val(val, plain_text):
                result["afghanistan_found"].append(val)
                
        for val in gt["japan"]:
            if check_val(val, plain_text):
                result["japan_found"].append(val)
                
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

chmod 666 /tmp/gapminder_analysis.json
echo "Analysis JSON saved to /tmp/gapminder_analysis.json"
cat /tmp/gapminder_analysis.json
echo "=== Export complete ==="