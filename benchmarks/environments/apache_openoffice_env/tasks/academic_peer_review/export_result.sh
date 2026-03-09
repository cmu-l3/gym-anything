#!/bin/bash
set -e

echo "=== Exporting Academic Peer Review Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Paths
OUTPUT_FILE="/home/ga/Documents/proposal_reviewed.odt"
RESULT_JSON="/tmp/task_result.json"

# Check file stats
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    else
        MODIFIED_DURING_TASK="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    MODIFIED_DURING_TASK="false"
fi

# Run Python script to parse ODT content
# We embed the python script to avoid dependency on external files
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

output_file = "/home/ga/Documents/proposal_reviewed.odt"
result = {
    "file_exists": False,
    "has_tracked_changes": False,
    "changes_found": [],
    "comments_found": [],
    "content_check": {
        "typo_fixed": False,
        "sentence_deleted": False
    },
    "error": None
}

if os.path.exists(output_file):
    result["file_exists"] = True
    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # ODT content is in content.xml
            content_xml = zf.read('content.xml').decode('utf-8')
            
            # Simple text parsing for XML elements to avoid namespace headaches with lxml/ET
            # (though we will use ET for robust parsing if possible, regex is good backup for ODF)
            
            # 1. Check for Track Changes enabled marker
            # <text:tracked-changes> element stores the list of changes
            if '<text:tracked-changes' in content_xml:
                result["has_tracked_changes"] = True
                
                # Extract change descriptions
                # Deletions often look like: <text:changed-region ...><text:deletion>...</text:deletion>
                # Insertions often look like: <text:changed-region ...><text:insertion>...</text:insertion>
                
                # Find deleted content
                # Note: ODF stores deleted text inside the text:tracked-changes section, usually 
                # inside a text:p in a text:deletion element
                deleted_blocks = re.findall(r'<text:deletion>(.*?)</text:deletion>', content_xml, re.DOTALL)
                for block in deleted_blocks:
                    text_content = re.sub(r'<[^>]+>', '', block).strip()
                    result["changes_found"].append({"type": "deletion", "text": text_content})
                    if "Nobel prize" in text_content:
                        result["content_check"]["sentence_deleted"] = True

                # Find inserted content
                # Insertions are referenced in tracked-changes but the text is usually inline in body 
                # wrapped in <text:change-start/> ... <text:change-end/>.
                # However, the existence of the change ID is enough to verify usage.
                # We can check the body text for "Drosophila" and verify it's there.
                
                body_content = re.sub(r'<text:tracked-changes.*?</text:tracked-changes>', '', content_xml, flags=re.DOTALL)
                if "Drosophila" in body_content and "Drosphila" not in body_content:
                     result["content_check"]["typo_fixed"] = True
                     # Check if it was tracked (heuristic: check if change-start/end tags exist near it)
                     # or simply rely on "has_tracked_changes" being true globally
            
            # 2. Check for Comments (Annotations)
            # <office:annotation>
            annotations = re.findall(r'<office:annotation.*?>(.*?)</office:annotation>', content_xml, re.DOTALL)
            for note in annotations:
                # Extract paragraph text from annotation
                note_text = re.sub(r'<[^>]+>', ' ', note).strip()
                result["comments_found"].append(note_text)

    except Exception as e:
        result["error"] = str(e)

# Output result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Add shell-level stats to the python-generated JSON
# We use jq if available, or python to merge
python3 << 'PYEOF'
import json
import sys

try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
except:
    data = {}

# Merge shell variables passed via environment or direct injection would be cleaner,
# but reading shell logic output is easiest here
data['file_stats'] = {
    'size_bytes': int(os.environ.get('FILE_SIZE', 0)),
    'modified_during_task': os.environ.get('MODIFIED_DURING_TASK', 'false') == 'true'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="