#!/bin/bash
# Export script for Property Loss Report
set -e

echo "=== Exporting Property Loss Report Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python Analysis Script inside the container
# This parses the ODT structure without needing complex libs on the verifier side
# It outputs a JSON summary of the document content.

python3 << 'PYEOF'
import json
import os
import zipfile
import re
import sys
import shutil
import time

# Configuration
output_path = "/home/ga/Documents/Claim_778492_Report.odt"
task_start_file = "/tmp/task_start_time.txt"
result_file = "/tmp/task_result.json"

result = {
    "file_exists": False,
    "file_size": 0,
    "created_during_task": False,
    "structure": {
        "image_count": 0,
        "table_count": 0,
        "heading1_count": 0,
        "has_claim_number": False,
        "has_insured_name": False,
        "has_grand_total": False,
        "has_captions": False
    },
    "error": None
}

# Check file existence
if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    
    # Check timestamp
    try:
        mtime = os.path.getmtime(output_path)
        with open(task_start_file, 'r') as f:
            start_time = float(f.read().strip())
        if mtime > start_time:
            result["created_during_task"] = True
    except Exception as e:
        pass

    # Parse ODT Content
    try:
        with zipfile.ZipFile(output_path, 'r') as z:
            # Check Images in Pictures/ folder
            # ODT usually stores images in 'Pictures/' directory within zip
            image_files = [n for n in z.namelist() if n.startswith('Pictures/') and len(n) > 9] # >9 to avoid just folder entry
            result["structure"]["image_count"] = len(image_files)

            # Read content.xml
            with z.open('content.xml') as f:
                content = f.read().decode('utf-8', errors='ignore')
                
                # Simple regex checks
                # Check for Claim Number "778492"
                if "778492" in content:
                    result["structure"]["has_claim_number"] = True
                
                # Check for Insured Name "Robert" and "Miller"
                if "Robert" in content and "Miller" in content:
                    result["structure"]["has_insured_name"] = True
                
                # Check for table tables
                result["structure"]["table_count"] = content.count('<table:table')
                
                # Check for table cell content "1,443.90" (Grand Total)
                if "1,443.90" in content:
                    result["structure"]["has_grand_total"] = True

                # Check for Heading 1 style
                # Look for <text:h ... text:outline-level="1">
                result["structure"]["heading1_count"] = content.count('text:outline-level="1"')

                # Check for Captions
                # Check for text like "Failed supply line"
                if "Failed supply line" in content and "Water damage to drywall" in content:
                    result["structure"]["has_captions"] = True
                    
    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

# Save result
with open(result_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Analysis complete. JSON saved to {result_file}")
PYEOF

# 3. Ensure permissions for copy_from_env
chmod 666 /tmp/task_result.json 2>/dev/null || true

# 4. Report status
if [ -f "/tmp/task_result.json" ]; then
    echo "Result JSON generated successfully."
    cat /tmp/task_result.json
else
    echo "ERROR: Failed to generate result JSON."
fi

echo "=== Export Complete ==="