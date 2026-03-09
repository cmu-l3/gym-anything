#!/bin/bash
echo "=== Exporting CPSC Recall Draft Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/Steamfast_Recall_Draft.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

# Check file existence and timestamps
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Python script to analyze ODT content structure
python3 << 'PYEOF'
import zipfile
import json
import re
import os
import sys

output_file = "/home/ga/Documents/Steamfast_Recall_Draft.odt"
result_data = {
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "has_release_header": False,
    "has_footer_marker": False,
    "has_phone": False,
    "has_hazard_text": False,
    "model_count": 0,
    "content_text": ""
}

if os.path.exists(output_file):
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            content_xml = zf.read('content.xml').decode('utf-8')
            
            # Remove XML tags for text analysis
            text_content = re.sub(r'<[^>]+>', ' ', content_xml)
            text_content = re.sub(r'\s+', ' ', text_content).strip()
            result_data["content_text"] = text_content
            
            # Structural Checks (XML based)
            # Count Heading 1 (outline-level="1")
            result_data["heading1_count"] = len(re.findall(r'text:outline-level="1"', content_xml))
            
            # Count Heading 2 (outline-level="2")
            result_data["heading2_count"] = len(re.findall(r'text:outline-level="2"', content_xml))
            
            # Count Tables
            result_data["table_count"] = len(re.findall(r'<table:table ', content_xml))
            
            # Content Checks (Text based)
            # Header
            if "FOR IMMEDIATE RELEASE" in text_content:
                result_data["has_release_header"] = True
                
            # Footer marker
            if "###" in text_content:
                result_data["has_footer_marker"] = True
                
            # Specific Data
            if "866-827-3362" in text_content:
                result_data["has_phone"] = True
                
            if "cord bushing" in text_content.lower() and "burn" in text_content.lower():
                result_data["has_hazard_text"] = True
                
            # Count how many model numbers are present
            models = ["SF-425", "SF-430", "SF-432", "SF-435", "SF-437", 
                      "SF-438", "SF-439", "SF-440", "SF-445", "SF-447"]
            found_models = sum(1 for m in models if m in text_content)
            result_data["model_count"] = found_models

    except Exception as e:
        print(f"Error parsing ODT: {e}", file=sys.stderr)

# Output analysis to JSON file
with open('/tmp/odt_analysis.json', 'w') as f:
    json.dump(result_data, f)
PYEOF

# Merge bash and python results
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "analysis": $(cat /tmp/odt_analysis.json 2>/dev/null || echo "{}")
}
EOF

# Set permissions for the verifier to read
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="