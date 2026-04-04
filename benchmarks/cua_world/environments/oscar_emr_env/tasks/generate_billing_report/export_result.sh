#!/bin/bash
# Export script for Generate Billing Report
# Checks for output file and extracts content for verification

echo "=== Exporting Billing Report Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for output file
# Agent might name it K013_Report.pdf, or .csv, or .txt
REPORT_FILE=""
for f in /home/ga/Documents/K013_Report.pdf /home/ga/Documents/K013_Report.csv /home/ga/Documents/K013_Report.txt; do
    if [ -f "$f" ]; then
        REPORT_FILE="$f"
        break
    fi
done

FILE_EXISTS="false"
FILE_EXT=""
EXTRACTED_TEXT=""
FILE_SIZE="0"
IS_NEW="false"

if [ -n "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_EXT="${REPORT_FILE##*.}"
    FILE_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    
    # Check creation time vs task start
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_NEW="true"
    fi

    echo "Found report file: $REPORT_FILE (Size: $FILE_SIZE bytes, New: $IS_NEW)"

    # Extract text content for verification
    if [ "$FILE_EXT" = "pdf" ]; then
        # Try pdftotext if installed, else python pypdf, else simple strings check
        if command -v pdftotext >/dev/null 2>&1; then
            EXTRACTED_TEXT=$(pdftotext "$REPORT_FILE" -)
        else
            # Fallback: simple strings extraction
            EXTRACTED_TEXT=$(strings "$REPORT_FILE" | grep -iE "K013|A007|Sarah|Chen" || echo "")
        fi
    else
        # CSV or Text
        EXTRACTED_TEXT=$(cat "$REPORT_FILE")
    fi
else
    echo "No matching report file found in /home/ga/Documents/"
fi

# 3. Read Ground Truth Data
# We need to pass the target/distractor IDs to the verifier
# CSV Format: type,invoice_id,provider,code,date
# We'll convert this to a JSON structure embedded in the result
GROUND_TRUTH_JSON=$(python3 -c "
import csv, json
try:
    data = {'targets': [], 'distractors': []}
    with open('/tmp/billing_ground_truth.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            item = {'id': row['invoice_id'], 'code': row['code'], 'date': row['date']}
            if row['type'] == 'TARGET':
                data['targets'].append(item)
            else:
                data['distractors'].append(item)
    print(json.dumps(data))
except Exception as e:
    print(json.dumps({'error': str(e)}))
")

# 4. Construct Result JSON
# Use python to safely escape the extracted text
python3 -c "
import json
import os

result = {
    'file_exists': $FILE_EXISTS,
    'file_path': '$REPORT_FILE',
    'is_new_file': $IS_NEW,
    'file_size': $FILE_SIZE,
    'file_extension': '$FILE_EXT',
    'extracted_text': '''$EXTRACTED_TEXT''',
    'ground_truth': $GROUND_TRUTH_JSON,
    'screenshot_path': '/tmp/task_final.png',
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/billing_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/billing_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/billing_result.json"
cat /tmp/billing_result.json | head -n 20
echo "...(truncated)..."

echo "=== Export Complete ==="