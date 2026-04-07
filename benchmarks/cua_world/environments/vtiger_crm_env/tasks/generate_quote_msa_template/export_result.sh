#!/bin/bash
echo "=== Exporting generate_quote_msa_template results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/msa_task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check for the exported PDF file
PDF_FOUND="false"
PDF_CREATED_DURING_TASK="false"
PDF_PATH="/home/ga/Documents/Enterprise_MSA.pdf"

# If not in exact path, try to find it in Downloads to give partial credit/helpful feedback
if [ ! -f "$PDF_PATH" ]; then
    RECENT_PDF=$(find /home/ga/Downloads /home/ga/Documents -name "*.pdf" -type f -mmin -60 | head -1)
    if [ -n "$RECENT_PDF" ]; then
        PDF_PATH="$RECENT_PDF"
    fi
fi

if [ -f "$PDF_PATH" ]; then
    PDF_FOUND="true"
    PDF_MTIME=$(stat -c %Y "$PDF_PATH" 2>/dev/null || echo "0")
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        PDF_CREATED_DURING_TASK="true"
    fi
    
    # Extract PDF Text using pdfminer (pre-installed in Python env)
    cat << 'PYEOF' > /tmp/extract_pdf.py
import sys
try:
    from pdfminer.high_level import extract_text
    text = extract_text(sys.argv[1])
    print(text)
except Exception as e:
    print(f"Error extracting PDF: {e}")
PYEOF
    
    python3 /tmp/extract_pdf.py "$PDF_PATH" > /tmp/pdf_extracted.txt 2>/dev/null
    PDF_TEXT=$(cat /tmp/pdf_extracted.txt 2>/dev/null | tr -d '\000-\011\013\014\016-\037' | head -c 5000)
else
    PDF_TEXT=""
fi

# 2. Check Database for the Print Template
DB_TEMPLATE_FOUND="false"
DB_TEMPLATE_BODY=""

# Query the vtiger_printtemplates table
TEMPLATE_ROW=$(vtiger_db_query "SELECT body FROM vtiger_printtemplates WHERE templatename='MSA Contract' LIMIT 1" | tr -d '\000-\011\013\014\016-\037')

if [ -n "$TEMPLATE_ROW" ]; then
    DB_TEMPLATE_FOUND="true"
    DB_TEMPLATE_BODY="$TEMPLATE_ROW"
fi

# Build JSON Result
RESULT_JSON=$(cat << JSONEOF
{
  "pdf_found": ${PDF_FOUND},
  "pdf_created_during_task": ${PDF_CREATED_DURING_TASK},
  "pdf_path": "$(json_escape "${PDF_PATH:-}")",
  "pdf_text": "$(json_escape "${PDF_TEXT:-}")",
  "db_template_found": ${DB_TEMPLATE_FOUND},
  "db_template_body": "$(json_escape "${DB_TEMPLATE_BODY:-}")",
  "task_start_time": ${TASK_START}
}
JSONEOF
)

safe_write_result "/tmp/generate_quote_msa_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/generate_quote_msa_result.json"
echo "$RESULT_JSON"
echo "=== generate_quote_msa_template export complete ==="