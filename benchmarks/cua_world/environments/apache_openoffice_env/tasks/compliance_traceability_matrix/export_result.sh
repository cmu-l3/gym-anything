#!/bin/bash
set -e

echo "=== Exporting Compliance Traceability Matrix Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Paths
OUTPUT_FILE="/home/ga/Documents/NeuroStim_SRS_v2.odt"
RESULT_JSON="/tmp/task_result.json"

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamp
FILE_EXISTS=false
FILE_MODIFIED=false
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    
    START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
        FILE_MODIFIED=true
    fi
fi

# 3. Deep Analysis of ODT Content (Python)
# We need to verify that active cross-references were used, not just text.
# We unzip content.xml and parse it.

cat > /tmp/analyze_odt.py << 'PYEOF'
import zipfile
import json
import re
import sys
import os

output_file = "/home/ga/Documents/NeuroStim_SRS_v2.odt"
json_output = "/tmp/analysis_result.json"

result = {
    "has_matrix_section": False,
    "table_found": False,
    "row_count": 0,
    "valid_cross_refs": 0,
    "data_matches": 0,
    "error": None
}

if not os.path.exists(output_file):
    with open(json_output, 'w') as f:
        json.dump(result, f)
    sys.exit(0)

try:
    with zipfile.ZipFile(output_file, 'r') as z:
        content = z.read('content.xml').decode('utf-8')
        
    # Check for Matrix Section Header
    # OpenOffice Active Headings usually look like <text:h ...>Verification Traceability Matrix</text:h>
    if re.search(r'<text:h[^>]*>Verification Traceability Matrix</text:h>', content, re.IGNORECASE):
        result["has_matrix_section"] = True
        
    # Find the table that likely contains the matrix
    # We look for a table that contains "Verification Protocol ID"
    table_pattern = re.compile(r'<table:table.*?>(.*?)</table:table>', re.DOTALL)
    tables = table_pattern.findall(content)
    
    matrix_table = None
    for t in tables:
        if "Verification Protocol ID" in t:
            matrix_table = t
            break
            
    if matrix_table:
        result["table_found"] = True
        
        # Count rows (excluding header ideally, but rough count is fine)
        rows = re.findall(r'<table:table-row>(.*?)</table:table-row>', matrix_table, re.DOTALL)
        result["row_count"] = len(rows)
        
        # Analyze rows for Cross References
        # A cross reference in ODT usually uses <text:reference-ref> or <text:bookmark-ref>
        # Example: <text:reference-ref text:ref-name="__RefHeading__...">REQ-SYS-01...</text:reference-ref>
        
        for row in rows:
            # Check for cross-reference tags
            # We are lenient: bookmark-ref OR reference-ref are both valid ways to link headings
            if '<text:reference-ref' in row or '<text:bookmark-ref' in row:
                result["valid_cross_refs"] += 1
                
            # Check for data presence (VP-xxx)
            # This ensures they actually filled it out
            if re.search(r'VP-\d{3}', row):
                result["data_matches"] += 1
                
except Exception as e:
    result["error"] = str(e)

with open(json_output, 'w') as f:
    json.dump(result, f)
PYEOF

python3 /tmp/analyze_odt.py

# 4. Merge Results
ANALYSIS=$(cat /tmp/analysis_result.json)

# Create final JSON
cat > "$RESULT_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE,
    "analysis": $ANALYSIS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chmod 666 "$RESULT_JSON"

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="