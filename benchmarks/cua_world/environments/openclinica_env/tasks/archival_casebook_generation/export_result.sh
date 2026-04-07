#!/bin/bash
echo "=== Exporting archival_casebook_generation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

PDF_PATH="/home/ga/Documents/CV-101_Casebook.pdf"
PDF_EXISTS="false"
PDF_SIZE="0"
PDF_MTIME="0"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH" 2>/dev/null || echo "0")
    PDF_MTIME=$(stat -c %Y "$PDF_PATH" 2>/dev/null || echo "0")
    
    # Copy for verifier
    cp "$PDF_PATH" /tmp/agent_casebook.pdf
    chmod 644 /tmp/agent_casebook.pdf
fi

# Check alternate locations just in case
if [ "$PDF_EXISTS" = "false" ]; then
    ALT_PDF=$(find /home/ga/Desktop /home/ga/Downloads /home/ga/Documents /home/ga -maxdepth 2 -name "CV-101*.pdf" -type f -newer /tmp/task_start_timestamp 2>/dev/null | head -1)
    if [ -n "$ALT_PDF" ]; then
        echo "Found PDF in alternate location: $ALT_PDF"
        PDF_EXISTS="true"
        PDF_SIZE=$(stat -c %s "$ALT_PDF" 2>/dev/null || echo "0")
        PDF_MTIME=$(stat -c %Y "$ALT_PDF" 2>/dev/null || echo "0")
        cp "$ALT_PDF" /tmp/agent_casebook.pdf
        chmod 644 /tmp/agent_casebook.pdf
    fi
fi

TEMP_JSON=$(mktemp /tmp/archival_casebook_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "pdf_exists": $PDF_EXISTS,
    "pdf_size_bytes": $PDF_SIZE,
    "pdf_mtime": $PDF_MTIME,
    "task_start": $TASK_START
}
EOF

rm -f /tmp/archival_casebook_result.json 2>/dev/null || sudo rm -f /tmp/archival_casebook_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/archival_casebook_result.json
chmod 666 /tmp/archival_casebook_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/archival_casebook_result.json"
cat /tmp/archival_casebook_result.json
echo "=== Export Complete ==="