#!/bin/bash
# Export results for Water Utility Pipe Infrastructure Failure Analysis task
echo "=== Exporting Water Utility Pipe results ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

# Initialize flags
FAILURE_RATE_EXISTS=false
FAILURE_RATE_ROWS=0
QUINTILE_COMPUTED=false

SURVIVAL_VW_EXISTS=false
SURVIVAL_WINDOW_USED=false

ESCALATION_VW_EXISTS=false
MATCH_RECOGNIZE_USED=false
ESCALATION_ROWS=0

PRIORITY_TBL_EXISTS=false
PRIORITY_ROWS=0
PRIORITY_COMPOSITE=false

BUDGET_VW_EXISTS=false
MODEL_USED=false
BUDGET_ROWS=0

CSV_EXISTS=false
CSV_ROWS=0
CSV_COLS=false

# --- 1. FAILURE_RATE_ANALYSIS table ---
TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'WATER_ENG' AND table_name = 'FAILURE_RATE_ANALYSIS';" "system")
if [ "${TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FAILURE_RATE_EXISTS=true
    FAILURE_RATE_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM water_eng.failure_rate_analysis;" "system")
    FAILURE_RATE_ROWS=${FAILURE_RATE_ROWS:-0}
    
    Q_CHECK=$(oracle_query_raw "SELECT COUNT(DISTINCT risk_quintile) FROM water_eng.failure_rate_analysis;" "system")
    if [ "${Q_CHECK:-0}" -ge 2 ] 2>/dev/null; then
        QUINTILE_COMPUTED=true
    fi
fi

# --- 2. PIPE_SURVIVAL_VW ---
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'WATER_ENG' AND view_name = 'PIPE_SURVIVAL_VW';" "system")
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SURVIVAL_VW_EXISTS=true
    
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'WATER_ENG' AND view_name = 'PIPE_SURVIVAL_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "OVER\s*\(|LAG\s*\(|LEAD\s*\(|CUME_DIST" 2>/dev/null; then
        SURVIVAL_WINDOW_USED=true
    fi
fi

# --- 3. ESCALATION_PATTERNS_VW ---
EVW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'WATER_ENG' AND view_name = 'ESCALATION_PATTERNS_VW';" "system")
if [ "${EVW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ESCALATION_VW_EXISTS=true
    ESCALATION_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM water_eng.escalation_patterns_vw;" "system")
    ESCALATION_ROWS=${ESCALATION_ROWS:-0}
    
    EVW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'WATER_ENG' AND view_name = 'ESCALATION_PATTERNS_VW';" "system" 2>/dev/null)
    if echo "$EVW_TEXT" | grep -qiE "MATCH_RECOGNIZE" 2>/dev/null; then
        MATCH_RECOGNIZE_USED=true
    fi
fi

# --- 4. REPLACEMENT_PRIORITY ---
PTBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'WATER_ENG' AND table_name = 'REPLACEMENT_PRIORITY';" "system")
if [ "${PTBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PRIORITY_TBL_EXISTS=true
    PRIORITY_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM water_eng.replacement_priority;" "system")
    PRIORITY_ROWS=${PRIORITY_ROWS:-0}
    
    # Check if multiple scores are used
    COLS_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_columns WHERE owner = 'WATER_ENG' AND table_name = 'REPLACEMENT_PRIORITY' AND column_name LIKE '%SCORE%';" "system")
    if [ "${COLS_CHECK:-0}" -ge 3 ] 2>/dev/null; then
        PRIORITY_COMPOSITE=true
    fi
fi

# --- 5. BUDGET_PROJECTION_VW ---
BVW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'WATER_ENG' AND view_name = 'BUDGET_PROJECTION_VW';" "system")
if [ "${BVW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    BUDGET_VW_EXISTS=true
    BUDGET_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM water_eng.budget_projection_vw;" "system")
    BUDGET_ROWS=${BUDGET_ROWS:-0}
    
    BVW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'WATER_ENG' AND view_name = 'BUDGET_PROJECTION_VW';" "system" 2>/dev/null)
    if echo "$BVW_TEXT" | grep -qiE "\bMODEL\b" 2>/dev/null; then
        MODEL_USED=true
    fi
fi

# --- 6. CSV Export ---
CSV_PATH="/home/ga/pipe_replacement_priorities.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    # check line count (subtract header)
    CSV_LINES=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_ROWS=$((CSV_LINES - 1))
    if [ "$CSV_ROWS" -lt 0 ]; then CSV_ROWS=0; fi
    
    # Header check
    HEADER=$(head -n 1 "$CSV_PATH" 2>/dev/null | tr '[:lower:]' '[:upper:]')
    if echo "$HEADER" | grep -qi "PIPE_ID" && echo "$HEADER" | grep -qi "MATERIAL"; then
        CSV_COLS=true
    fi
fi

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "failure_rate_exists": $FAILURE_RATE_EXISTS,
    "failure_rate_rows": $FAILURE_RATE_ROWS,
    "quintile_computed": $QUINTILE_COMPUTED,
    
    "survival_vw_exists": $SURVIVAL_VW_EXISTS,
    "survival_window_used": $SURVIVAL_WINDOW_USED,
    
    "escalation_vw_exists": $ESCALATION_VW_EXISTS,
    "match_recognize_used": $MATCH_RECOGNIZE_USED,
    "escalation_rows": $ESCALATION_ROWS,
    
    "priority_tbl_exists": $PRIORITY_TBL_EXISTS,
    "priority_rows": $PRIORITY_ROWS,
    "priority_composite": $PRIORITY_COMPOSITE,
    
    "budget_vw_exists": $BUDGET_VW_EXISTS,
    "model_used": $MODEL_USED,
    "budget_rows": $BUDGET_ROWS,
    
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_cols": $CSV_COLS,
    
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    ${GUI_EVIDENCE}
}
EOF

rm -f /tmp/water_pipe_result.json 2>/dev/null || sudo rm -f /tmp/water_pipe_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/water_pipe_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/water_pipe_result.json
chmod 666 /tmp/water_pipe_result.json 2>/dev/null || sudo chmod 666 /tmp/water_pipe_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/water_pipe_result.json