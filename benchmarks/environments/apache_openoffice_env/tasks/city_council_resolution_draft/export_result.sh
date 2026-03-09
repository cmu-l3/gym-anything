#!/bin/bash
echo "=== Exporting Resolution Draft Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file
OUTPUT_FILE="/home/ga/Documents/Resolution_2025_042.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Python script to analyze ODT internal structure (XML)
# We need to check styles.xml for line numbering configuration
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys

output_path = "/home/ga/Documents/Resolution_2025_042.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "line_numbering_enabled": False,
    "whereas_count": 0,
    "content_text": "",
    "timestamp_valid": False
}

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    
    # Check timestamp
    mtime = os.path.getmtime(output_path)
    try:
        start_time = float(open("/tmp/task_start_time.txt").read().strip())
        if mtime > start_time:
            result["timestamp_valid"] = True
    except:
        pass

    try:
        with zipfile.ZipFile(output_path, 'r') as z:
            # 1. Check styles.xml for line numbering
            # OpenOffice usually stores this in styles.xml under <text:linenumbering-configuration>
            # Attribute text:number-lines="true"
            if 'styles.xml' in z.namelist():
                styles_xml = z.read('styles.xml').decode('utf-8', errors='ignore')
                # Check for explicit enabled config
                if 'text:number-lines="true"' in styles_xml:
                    result["line_numbering_enabled"] = True
                # Sometimes it exists but implies false if not set, or is missing if disabled
                # If the element exists, check attributes
                elif '<text:linenumbering-configuration' in styles_xml:
                    # If the tag is present, check if it has number-lines="false"
                    if 'text:number-lines="false"' not in styles_xml:
                         # Defaults might vary, but usually enabling it adds the tag or sets it to true
                         # Let's check for style:number-lines="true" (some versions)
                         pass
            
            # 2. Extract content text
            if 'content.xml' in z.namelist():
                content_xml = z.read('content.xml').decode('utf-8', errors='ignore')
                # Strip tags for text analysis
                plain_text = re.sub(r'<[^>]+>', ' ', content_xml)
                result["content_text"] = " ".join(plain_text.split())
                
                # Count WHEREAS clauses (simple heuristic)
                # Look for WHEREAS followed by text
                result["whereas_count"] = len(re.findall(r'\bWHEREAS\b', result["content_text"], re.IGNORECASE))

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

# Move result to safe location and permissions
cp /tmp/task_result.json /tmp/safe_task_result.json
chmod 666 /tmp/safe_task_result.json

echo "Result exported to /tmp/safe_task_result.json"
cat /tmp/safe_task_result.json
echo "=== Export Complete ==="