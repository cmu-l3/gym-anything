#!/bin/bash
echo "=== Exporting nasa_meteorite_analysis_write task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Capture final state screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/meteorite_task_end.png" 2>/dev/null || true

# Parse the document using a Python script to prevent bash interpolation issues
python3 << 'PYEOF' > /tmp/meteorite_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/meteorite_analysis.json
import json
import zipfile
import xml.etree.ElementTree as ET
import re
import os

result = {
    "file_exists": False,
    "file_size": 0,
    "file_modified": False,
    "generator": "",
    "has_hoba": False,
    "has_cape_york": False,
    "has_campo": False,
    "has_60000": False,
    "has_36200": False,
    "has_50000": False,
    "has_kg": False,
    "text_content": "",
    "error": None
}

odt_file = "/home/ga/Documents/heaviest_meteorites.odt"
task_start_file = "/tmp/meteorite_task_start_ts"

# Get task start timestamp
try:
    with open(task_start_file, 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

# Check file stats and content
if os.path.exists(odt_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(odt_file)
    result["file_modified"] = os.path.getmtime(odt_file) > task_start
    
    try:
        with zipfile.ZipFile(odt_file, 'r') as z:
            # Verify GUI was used (Anti-gaming check)
            if 'meta.xml' in z.namelist():
                meta = z.read('meta.xml').decode('utf-8')
                if 'AbiWord' in meta:
                    result['generator'] = 'AbiWord'
            
            # Check content for task requirements
            if 'content.xml' in z.namelist():
                content = z.read('content.xml').decode('utf-8')
                
                # Strip XML tags to get plain text
                plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
                plain_text = plain_text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
                
                result["text_content"] = plain_text[:2000]  # Truncate for JSON safely
                
                # Check for meteorite names
                result["has_hoba"] = 'hoba' in plain_text
                result["has_cape_york"] = 'cape york' in plain_text
                result["has_campo"] = 'campo del cielo' in plain_text
                
                # Check for converted mass values
                # Lookaround assertions ensure we match exactly the kg amount, not a substring of the gram amount
                # Accommodates 60000, 60,000, 60000.0, 60000.00, etc.
                result["has_60000"] = bool(re.search(r'(?<!\d)60,?000(?:\.0+)?(?!\d)', plain_text))
                result["has_36200"] = bool(re.search(r'(?<!\d)36,?200(?:\.0+)?(?!\d)', plain_text))
                result["has_50000"] = bool(re.search(r'(?<!\d)50,?000(?:\.0+)?(?!\d)', plain_text))
                
                # Check for unit designation
                result["has_kg"] = bool(re.search(r'\b(kg|kilograms?)\b', plain_text))
                
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

chmod 666 /tmp/meteorite_analysis.json
echo "Result saved to /tmp/meteorite_analysis.json"
cat /tmp/meteorite_analysis.json
echo "=== Export complete ==="