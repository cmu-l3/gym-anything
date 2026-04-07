#!/bin/bash
echo "=== Exporting compose_patient_letter results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_doc_count.txt 2>/dev/null || echo "0")
TARGET_PID=9999

# 3. Query Database for Results
# We look for documents created for the target PID. 
# NOSH stores document metadata in the 'documents' table.
# Columns typically include: documents_id, pid, type, documents_url, documents_desc, documents_date, etc.
# Note: NOSH schemas can vary, but usually 'documents_desc' or 'documents_view' holds the title/subject.

echo "Querying database for new documents..."

# Get count of documents now
FINAL_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM documents WHERE pid=$TARGET_PID;" 2>/dev/null || echo "0")

# Get details of the most recent document for this patient
# We check columns that typically store the subject/title. In NOSH, 'documents_desc' often holds the title.
DOC_JSON=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "
    SELECT JSON_OBJECT(
        'id', documents_id,
        'pid', pid,
        'date', documents_date,
        'description', documents_desc,
        'url', documents_url,
        'timestamp', UNIX_TIMESTAMP(documents_date)
    )
    FROM documents 
    WHERE pid=$TARGET_PID 
    ORDER BY documents_id DESC LIMIT 1;
" 2>/dev/null)

if [ -z "$DOC_JSON" ]; then
    DOC_JSON="null"
fi

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_doc_count": $INITIAL_COUNT,
    "final_doc_count": $FINAL_COUNT,
    "latest_document": $DOC_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="