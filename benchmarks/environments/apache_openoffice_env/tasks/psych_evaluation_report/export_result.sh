#!/bin/bash
echo "=== Exporting Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# 2. Define Paths
OUTPUT_FILE="/home/ga/Documents/Confidential_Psych_Eval_Thorne_M.odt"
RESULT_JSON="/tmp/task_result.json"

# 3. Analyze the ODT file using Python
# We extract content.xml and styles.xml to verify the header, table, and data
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys

output_path = "/home/ga/Documents/Confidential_Psych_Eval_Thorne_M.odt"
task_start_path = "/tmp/task_start_time.txt"

result = {
    "file_exists": False,
    "file_size": 0,
    "created_during_task": False,
    "has_confidential_header": False,
    "header_location": "none",
    "table_count": 0,
    "scores_found": [],
    "diagnosis_code_found": False,
    "patient_name_found": False,
    "error": None
}

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    
    # Check timestamp
    try:
        with open(task_start_path, 'r') as f:
            start_time = int(f.read().strip())
        mtime = int(os.path.getmtime(output_path))
        if mtime > start_time:
            result["created_during_task"] = True
    except Exception:
        pass # Ignore timestamp errors if file missing

    try:
        with zipfile.ZipFile(output_path, 'r') as zf:
            # Read XML content
            content_xml = zf.read('content.xml').decode('utf-8', errors='ignore')
            styles_xml = ""
            if 'styles.xml' in zf.namelist():
                styles_xml = zf.read('styles.xml').decode('utf-8', errors='ignore')

            # 1. Verify Header "CONFIDENTIAL"
            # Headers are typically defined in styles.xml under style:master-page -> style:header
            header_regex = re.compile(r'CONFIDENTIAL', re.IGNORECASE)
            
            if header_regex.search(styles_xml):
                result["has_confidential_header"] = True
                result["header_location"] = "styles.xml (Correct for Headers)"
            elif header_regex.search(content_xml):
                # It might be in the body, which is less ideal but strictly speaking contains the text
                # However, for 100% points we want it in the header style
                result["header_location"] = "content.xml (Body Text)"
            
            # 2. Verify Table
            # Look for <table:table> tags in content.xml
            result["table_count"] = content_xml.count('<table:table')

            # 3. Verify Scores (112, 98, 105, 88, 85)
            # We look for these numbers specifically in the content
            expected_scores = ["112", "98", "105", "88", "85"]
            found_scores = []
            for score in expected_scores:
                if f">{score}<" in content_xml or f">{score} <" in content_xml:
                    found_scores.append(score)
            result["scores_found"] = found_scores

            # 4. Verify Diagnosis Code (314.01)
            if "314.01" in content_xml:
                result["diagnosis_code_found"] = True

            # 5. Verify Patient Name
            if "Marcus" in content_xml and "Thorne" in content_xml:
                result["patient_name_found"] = True

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# 4. Permission handling
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="