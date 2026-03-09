#!/bin/bash
echo "=== Exporting Policy Manual Adaptation Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

OUTPUT_FILE="/home/ga/Documents/maricopa_cd_response_manual.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if output file exists and timestamps
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# 3. Python script to verify ODT content structure using odfpy
# We use python to output a JSON analysis of the file content
echo "Analyzing document content..."

python3 -c "
import sys
import json
import zipfile
import re
from odf.opendocument import load

result = {
    'file_exists': $FILE_EXISTS,
    'file_size': $FILE_SIZE,
    'created_during_task': $CREATED_DURING_TASK,
    'replacements_score_data': {},
    'formatting_check': {},
    'header_check': False,
    'revision_table_check': False,
    'content_preserved_count': 0
}

if not result['file_exists']:
    print(json.dumps(result))
    sys.exit(0)

try:
    doc = load('$OUTPUT_FILE')
    
    # --- Extract all text for replacement checks ---
    # We'll use a crude XML extraction for text counting to be robust
    with zipfile.ZipFile('$OUTPUT_FILE', 'r') as z:
        content_xml = z.read('content.xml').decode('utf-8')
        styles_xml = z.read('styles.xml').decode('utf-8')
    
    # Normalize text
    plain_text = re.sub(r'<[^>]+>', ' ', content_xml)
    
    # 1. Replacement Checks
    # We look for absence of OLD strings and presence of NEW strings
    checks = [
        ('Arizona Department of Health Services', 'Maricopa County Department of Public Health'),
        ('State Epidemiology and Response Division', 'County Epidemiology Unit'),
        ('(602) 555-0147', '(602) 555-0328'),
        ('@azdhs.gov', '@maricopa.gov')
    ]
    
    for old, new in checks:
        result['replacements_score_data'][old] = plain_text.count(old)
        result['replacements_score_data'][new] = plain_text.count(new)

    # 2. Formatting Checks (Heading 1)
    # We look for <text:h ... text:outline-level='1'> ... specific titles ... </text:h>
    # Since XML parsing with regex is fragile, we look for the pattern loosely
    # We want to see if 'Outbreak Investigation Procedures' is inside a text:h tag
    
    # Extract headings specifically
    # Using regex to find content inside text:h tags with outline-level='1'
    headings = re.findall(r'<text:h[^>]*text:outline-level=\"1\"[^>]*>(.*?)</text:h>', content_xml, re.DOTALL)
    headings_text = ' '.join(headings)
    
    result['formatting_check']['section_3_fixed'] = 'Outbreak Investigation Procedures' in headings_text
    result['formatting_check']['section_6_fixed'] = 'Contact Tracing Operations' in headings_text
    result['formatting_check']['section_9_fixed'] = 'Resource Management and Logistics' in headings_text
    result['formatting_check']['revision_history_heading'] = 'Revision History' in headings_text
    result['formatting_check']['total_h1_count'] = len(headings)

    # 3. Header Check
    # Headers are usually in styles.xml under <style:header> or <style:header-left>
    # or referenced in content.xml if direct. Usually styles.xml for standard headers.
    result['header_check'] = 'MARICOPA COUNTY' in styles_xml

    # 4. Revision Table Check
    # Look for table:table and specific cell content
    has_table = '<table:table' in content_xml
    has_author = 'Sandoval-Cruz' in content_xml
    has_version = '2.0' in content_xml
    result['revision_table_check'] = has_table and has_author and has_version

    # 5. Content Preservation
    # Count paragraphs
    result['content_preserved_count'] = content_xml.count('<text:p')

except Exception as e:
    result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# 4. Cleanup and Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="