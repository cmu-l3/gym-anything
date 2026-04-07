#!/bin/bash
# Export script for Data Quality Pedigree task
# Runs after the agent finishes

source /workspace/scripts/task_utils.sh

# Fallback for utils
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi
if ! type derby_query &>/dev/null; then
    derby_query() { echo ""; }
fi

echo "=== Exporting Data Quality Pedigree Result ==="

# 1. Take Final Screenshot
take_screenshot /tmp/task_end_screenshot.png
echo "Final screenshot saved"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/LCA_Results"
REPORT_FILE="$RESULTS_DIR/data_quality_report.csv"

# 2. Check for Output File
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
HAS_DQ_KEYWORDS="false"
HAS_PROCESS_KEYWORDS="false"

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check content for keywords
    grep -qi "Reliability\|Completeness\|Temporal\|Geographical\|Technological" "$REPORT_FILE" 2>/dev/null && HAS_DQ_KEYWORDS="true"
    grep -qi "coal\|electricity\|power" "$REPORT_FILE" 2>/dev/null && HAS_PROCESS_KEYWORDS="true"
fi

# 3. Close OpenLCA to query Derby Database
echo "Closing OpenLCA for database verification..."
close_openlca
sleep 5

# 4. Verify Database State using Derby
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find the largest/active database
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    current_size=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${current_size:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${current_size:-0}"
        ACTIVE_DB="$db_path"
    fi
done

DQ_SYSTEM_COUNT=0
DQ_INDICATOR_COUNT=0
PROCESS_WITH_DQ=0
EXCHANGES_WITH_DQ=0
DQ_SYSTEM_NAME=""

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    echo "Querying database: $(basename "$ACTIVE_DB")"
    
    # A. Check for DQ Systems
    DQ_SYSTEM_COUNT=$(derby_query "$ACTIVE_DB" "SELECT COUNT(*) FROM TBL_DQ_SYSTEMS" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    # B. Check for 5 Indicators (Reliability etc.)
    # We check if there's any system with exactly 5 indicators
    # Note: TBL_DQ_INDICATORS links to TBL_DQ_SYSTEMS via F_DQ_SYSTEM
    DQ_INDICATOR_COUNT=$(derby_query "$ACTIVE_DB" "SELECT COUNT(*) FROM TBL_DQ_INDICATORS" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    # C. Check Process Assignment (F_DQ_SYSTEM is not null AND DQ_ENTRY is not null)
    # DQ_ENTRY looks like '(2;1;3;...)'
    PROCESS_WITH_DQ=$(derby_query "$ACTIVE_DB" "SELECT COUNT(*) FROM TBL_PROCESSES WHERE F_DQ_SYSTEM IS NOT NULL AND DQ_ENTRY LIKE '%;%'" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    # D. Check Exchange Assignment (DQ_ENTRY is not null)
    EXCHANGES_WITH_DQ=$(derby_query "$ACTIVE_DB" "SELECT COUNT(*) FROM TBL_EXCHANGES WHERE DQ_ENTRY LIKE '%;%'" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    # E. Get Name of DQ System (if exists)
    if [ "${DQ_SYSTEM_COUNT:-0}" -gt 0 ]; then
        DQ_SYSTEM_NAME=$(derby_query "$ACTIVE_DB" "SELECT NAME FROM TBL_DQ_SYSTEMS FETCH FIRST 1 ROWS ONLY" | grep -v "^ij>" | grep -v "rows selected" | grep -v "^NAME" | head -1 | xargs || echo "")
    fi
    
    echo "  DQ Systems: $DQ_SYSTEM_COUNT"
    echo "  Processes with DQ: $PROCESS_WITH_DQ"
    echo "  Exchanges with DQ: $EXCHANGES_WITH_DQ"
else
    echo "No valid database found to query."
fi

# 5. Capture Window/Log State (for fallback)
# Since we closed the app, we check logs for evidence
LOG_FILE="/tmp/openlca_ga.log"
DQ_LOG_EVIDENCE="false"
if [ -f "$LOG_FILE" ]; then
    grep -qi "DataQuality\|DQSystem" "$LOG_FILE" 2>/dev/null && DQ_LOG_EVIDENCE="true"
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "has_dq_keywords": $HAS_DQ_KEYWORDS,
    "has_process_keywords": $HAS_PROCESS_KEYWORDS,
    "db_found": $([ -n "$ACTIVE_DB" ] && echo "true" || echo "false"),
    "dq_system_count": ${DQ_SYSTEM_COUNT:-0},
    "dq_indicator_count": ${DQ_INDICATOR_COUNT:-0},
    "dq_system_name": "$DQ_SYSTEM_NAME",
    "process_with_dq_count": ${PROCESS_WITH_DQ:-0},
    "exchanges_with_dq_count": ${EXCHANGES_WITH_DQ:-0},
    "dq_log_evidence": $DQ_LOG_EVIDENCE,
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json