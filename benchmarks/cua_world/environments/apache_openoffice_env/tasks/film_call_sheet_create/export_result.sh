#!/bin/bash
echo "=== Exporting Film Call Sheet Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define paths
OUTPUT_FILE="/home/ga/Documents/Call_Sheet_Day_14.odt"
RESULT_JSON="/tmp/task_result.json"

# 3. Python script to analyze the ODT file
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import datetime

output_file = "/home/ga/Documents/Call_Sheet_Day_14.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "table_count": 0,
    "has_image": False,
    "has_title": False,
    "has_day_info": False,
    "has_scene_42": False,
    "has_actor_elena": False,
    "has_time_0545": False,
    "has_hospital_info": False,
    "raw_text_preview": "",
    "export_timestamp": datetime.datetime.now().isoformat()
}

if os.path.exists(output_file):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_file)
    
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # 1. Check content.xml
            content = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Count Tables
            result["table_count"] = len(re.findall(r'<table:table\b', content))
            
            # Check for embedded image (draw:frame)
            result["has_image"] = '<draw:frame' in content or '<draw:image' in content
            
            # Extract plain text for content searching
            plain_text = re.sub(r'<[^>]+>', ' ', content)
            # Normalize whitespace
            plain_text = re.sub(r'\s+', ' ', plain_text).strip()
            
            # Store a preview
            result["raw_text_preview"] = plain_text[:500]
            
            # Check specific content strings (case insensitive where appropriate)
            text_lower = plain_text.lower()
            
            result["has_title"] = "midnight echo" in text_lower
            result["has_day_info"] = "day 14" in text_lower
            result["has_scene_42"] = "42" in plain_text # Scene number
            result["has_actor_elena"] = "elena rostova" in text_lower
            result["has_time_0545"] = "05:45" in plain_text # Specific pickup time
            result["has_hospital_info"] = "hospital" in text_lower or "harborview" in text_lower
            
    except Exception as e:
        result["error"] = str(e)

# Write result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# 4. Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="