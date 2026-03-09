#!/bin/bash
echo "=== Exporting hl7_batch_file_processor task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_batchproc.png

# Get initial and current channel counts
INITIAL=$(cat /tmp/initial_batchproc_channel_count 2>/dev/null || echo "0")
CURRENT=$(get_channel_count)

echo "Initial channel count: $INITIAL"
echo "Current channel count: $CURRENT"

# Locate the batch processor channel
CHANNEL_EXISTS="false"
CHANNEL_ID=""
CHANNEL_NAME=""
CHANNEL_STATUS="unknown"
HAS_FILE_READER="false"
HAS_BATCH_PROCESSING="false"
HAS_JS_PREPROCESSOR="false"
HAS_DB_WRITER="false"
HAS_ARCHIVE_CONFIG="false"
FILE_FILTER_CORRECT="false"

# Search for channel by name patterns
CHANNEL_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%batch%' OR (LOWER(name) LIKE '%nightly%' AND LOWER(name) LIKE '%hl7%') OR (LOWER(name) LIKE '%file%' AND LOWER(name) LIKE '%processor%');" 2>/dev/null || true)

if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f1)
    CHANNEL_NAME=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f2)
    echo "Found batch processor channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"
fi

# Fallback: any new channel
if [ "$CHANNEL_EXISTS" = "false" ] && [ "$CURRENT" -gt "$INITIAL" ]; then
    LATEST_DATA=$(query_postgres "SELECT id, name FROM channel ORDER BY revision DESC LIMIT 1;" 2>/dev/null || true)
    if [ -n "$LATEST_DATA" ]; then
        CHANNEL_EXISTS="true"
        CHANNEL_ID=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f1)
        CHANNEL_NAME=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f2)
        echo "Fallback - Found latest channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"
    fi
fi

# Analyze channel XML
if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null || true)

    # Check for File Reader source connector (not TCP)
    if echo "$CHANNEL_XML" | grep -qi "FileReceiverProperties\|fileReceiver\|directoryPath\|hl7_batch_inbox"; then
        HAS_FILE_READER="true"
    fi

    # Check for batch processing configuration
    if echo "$CHANNEL_XML" | grep -qi "processBatch.*true\|batchScript\|batch.*process"; then
        HAS_BATCH_PROCESSING="true"
    fi

    # Check for JavaScript preprocessor with batch splitting logic
    if echo "$CHANNEL_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
# Look for preprocessor with batch/BHS/split logic
has_preproc = bool(re.search(r'preprocessor|BatchScript|BHS|BTS|split.*message|individual.*message', xml, re.IGNORECASE))
print('true' if has_preproc else 'false')
" 2>/dev/null | grep -q "true"; then
        HAS_JS_PREPROCESSOR="true"
    fi

    # Check for Database Writer with batch_processing_log
    if echo "$CHANNEL_XML" | grep -qi "DatabaseDispatcher\|batch_processing_log\|patient_mrn.*message_type"; then
        HAS_DB_WRITER="true"
    fi

    # Check for archive/move configuration
    if echo "$CHANNEL_XML" | grep -qi "moveToDirectory\|batch_archive\|hl7_batch_archive\|MOVE\|afterProcessingAction"; then
        HAS_ARCHIVE_CONFIG="true"
    fi

    # Check file filter
    if echo "$CHANNEL_XML" | grep -qi "\.hl7\|fileFilter.*hl7\|\*\.hl7"; then
        FILE_FILTER_CORRECT="true"
    fi

    # Check deployment
    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$CHANNEL_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        CHANNEL_STATUS="deployed"
    fi
    API_STATUS=$(get_channel_status_api "$CHANNEL_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        CHANNEL_STATUS="$API_STATUS"
    fi
fi

# Check batch_processing_log table
BATCH_TABLE_EXISTS="false"
BATCH_ROW_COUNT=0

BATCH_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='batch_processing_log';" 2>/dev/null || echo "0")
if [ "$BATCH_CHECK" -gt 0 ] 2>/dev/null; then
    BATCH_TABLE_EXISTS="true"
    BATCH_ROW_COUNT=$(query_postgres "SELECT COUNT(*) FROM batch_processing_log;" 2>/dev/null || echo "0")
fi

# Check if files were moved to archive (indicates channel actually ran)
ARCHIVE_HAS_FILES="false"
ARCHIVE_FILE_COUNT=0
if [ -d "/home/ga/hl7_batch_archive" ]; then
    ARCHIVE_FILE_COUNT=$(ls /home/ga/hl7_batch_archive/*.hl7 2>/dev/null | wc -l || echo "0")
    if [ "$ARCHIVE_FILE_COUNT" -gt 0 ]; then
        ARCHIVE_HAS_FILES="true"
    fi
fi

echo "Channel: $CHANNEL_NAME, Status: $CHANNEL_STATUS"
echo "File Reader: $HAS_FILE_READER, Batch Processing: $HAS_BATCH_PROCESSING"
echo "JS Preprocessor: $HAS_JS_PREPROCESSOR, DB Writer: $HAS_DB_WRITER"
echo "Archive Config: $HAS_ARCHIVE_CONFIG, File Filter: $FILE_FILTER_CORRECT"
echo "batch_processing_log: $BATCH_TABLE_EXISTS ($BATCH_ROW_COUNT rows)"
echo "Archive files: $ARCHIVE_HAS_FILES ($ARCHIVE_FILE_COUNT files)"

JSON_CONTENT=$(cat <<EOF
{
    "initial_count": $INITIAL,
    "current_count": $CURRENT,
    "channel_exists": $CHANNEL_EXISTS,
    "channel_id": "$CHANNEL_ID",
    "channel_name": "$CHANNEL_NAME",
    "channel_status": "$CHANNEL_STATUS",
    "has_file_reader": $HAS_FILE_READER,
    "has_batch_processing": $HAS_BATCH_PROCESSING,
    "has_js_preprocessor": $HAS_JS_PREPROCESSOR,
    "has_db_writer": $HAS_DB_WRITER,
    "has_archive_config": $HAS_ARCHIVE_CONFIG,
    "file_filter_correct": $FILE_FILTER_CORRECT,
    "batch_table_exists": $BATCH_TABLE_EXISTS,
    "batch_row_count": $BATCH_ROW_COUNT,
    "archive_has_files": $ARCHIVE_HAS_FILES,
    "archive_file_count": $ARCHIVE_FILE_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/hl7_batch_file_processor_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/hl7_batch_file_processor_result.json"
cat /tmp/hl7_batch_file_processor_result.json
echo "=== Export complete ==="
