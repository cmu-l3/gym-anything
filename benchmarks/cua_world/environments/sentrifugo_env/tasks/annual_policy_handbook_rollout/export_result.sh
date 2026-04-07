#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

take_screenshot /tmp/task_final.png

# 1. Export database dump for string matching
# We export without create info, triggers, etc. just to capture the textual data
docker exec sentrifugo-db mysqldump -u root -prootpass123 sentrifugo --no-create-info --skip-triggers --compact > /tmp/sentrifugo_db_dump.sql 2>/dev/null

# 2. Hash all PDF files in the Sentrifugo uploads directory
UPLOAD_DIR="/var/www/html/sentrifugo/public/uploads"
find "$UPLOAD_DIR" -type f -name "*.pdf" -exec md5sum {} \; > /tmp/uploaded_pdf_hashes.txt 2>/dev/null || true
# Also include any newly created files just in case they don't have .pdf extension
find "$UPLOAD_DIR" -type f -newer /tmp/task_start_timestamp -exec md5sum {} \; >> /tmp/uploaded_pdf_hashes.txt 2>/dev/null || true

# Deduplicate the hashes
sort -u /tmp/uploaded_pdf_hashes.txt > /tmp/uploaded_pdf_hashes_clean.txt 2>/dev/null || true

# 3. Create JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="