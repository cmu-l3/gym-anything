#!/bin/bash
# export_result.sh - Post-task hook
# Analyzes the output PDF for annotations

echo "=== Exporting PDF Markup Results ==="

# 1. Record End Time and Screenshot
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define Paths
OUTPUT_PDF="/home/ga/Desktop/FMLA_FactSheet_Reviewed.pdf"

# 3. Analyze PDF content using Python
# We use a robust script that searches the raw PDF structure for annotation markers
# This avoids needing complex PDF libraries if they aren't installed
python3 << 'PYEOF'
import json
import os
import re
import sys

output_path = "/home/ga/Desktop/FMLA_FactSheet_Reviewed.pdf"
task_start = int(open("/tmp/task_start_time.txt").read().strip())
result = {
    "file_exists": False,
    "file_created_during_task": False,
    "has_highlight": False,
    "has_text_note": False,
    "has_ink": False,
    "has_target_text": False,
    "file_size": 0
}

if os.path.exists(output_path):
    result["file_exists"] = True
    stat = os.stat(output_path)
    result["file_size"] = stat.st_size
    
    # Check timestamp
    if stat.st_mtime > task_start:
        result["file_created_during_task"] = True

    try:
        # Read file as binary to find PDF markers
        with open(output_path, 'rb') as f:
            content = f.read()
            
            # Convert to string for regex searching (ignoring binary garbage)
            # PDF keywords are ASCII
            content_str = content.decode('latin1', errors='ignore')
            
            # Check for Highlight Annotation
            # Structure: /Subtype /Highlight
            if re.search(r'/Subtype\s*/Highlight', content_str):
                result["has_highlight"] = True
                
            # Check for Text/FreeText Annotation
            # Edge adds text as /Subtype /FreeText
            if re.search(r'/Subtype\s*/FreeText', content_str):
                result["has_text_note"] = True
                
            # Check for Ink/Drawing Annotation
            # Edge uses /Subtype /Ink for drawings
            if re.search(r'/Subtype\s*/Ink', content_str):
                result["has_ink"] = True
                
            # Check for specific text content "Verify tenure in HRIS"
            # Text in PDFs is often in parentheses: (Verify tenure in HRIS)
            # Or split: (Verify) ... (tenure)
            target = "Verify tenure in HRIS"
            
            # Simple check
            if target in content_str:
                result["has_target_text"] = True
            else:
                # Check for PDF encoded string format
                # e.g., (Verify tenure in HRIS)
                if f"({target})" in content_str:
                     result["has_target_text"] = True
                
    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

print("Analysis complete:", json.dumps(result))
PYEOF

# 4. Secure the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="