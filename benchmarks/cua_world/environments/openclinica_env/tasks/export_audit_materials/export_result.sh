#!/bin/bash
echo "=== Exporting export_audit_materials result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_end_screenshot.png

TARGET_DIR="/home/ga/Documents/Audit_Materials"
DIR_EXISTS="false"
PDF_COUNT=0
FILES_CREATED_DURING_TASK="false"

if [ -d "$TARGET_DIR" ]; then
    DIR_EXISTS="true"
    PDF_COUNT=$(find "$TARGET_DIR" -name "*.pdf" | wc -l)
    
    # Check if any PDFs are newer than the setup timestamp marker
    NEW_PDFS=$(find "$TARGET_DIR" -name "*.pdf" -newer /tmp/task_start_timestamp 2>/dev/null | wc -l)
    if [ "$NEW_PDFS" -gt 0 ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
    
    # Tar the directory contents so the verifier can copy them out
    tar -czf /tmp/audit_materials.tar.gz -C "$TARGET_DIR" . 2>/dev/null || true
fi

# Build JSON report
TEMP_JSON=$(mktemp /tmp/audit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dir_exists": $DIR_EXISTS,
    "pdf_count": $PDF_COUNT,
    "files_created_during_task": $FILES_CREATED_DURING_TASK
}
EOF

# Move to standard location safely
rm -f /tmp/export_audit_materials_result.json 2>/dev/null || sudo rm -f /tmp/export_audit_materials_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/export_audit_materials_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/export_audit_materials_result.json
chmod 666 /tmp/export_audit_materials_result.json 2>/dev/null || sudo chmod 666 /tmp/export_audit_materials_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved:"
cat /tmp/export_audit_materials_result.json
echo ""
echo "=== Export Complete ==="