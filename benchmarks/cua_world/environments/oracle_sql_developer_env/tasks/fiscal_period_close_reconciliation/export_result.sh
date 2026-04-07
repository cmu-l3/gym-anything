#!/bin/bash
# Export results for Fiscal Period Close Reconciliation task
echo "=== Exporting Fiscal Close results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Sanitize: ensure a variable holds a valid integer, default to given fallback
sanitize_int() { local val="$1" default="$2"; if [[ "$val" =~ ^[0-9]+$ ]]; then echo "$val"; else echo "$default"; fi; }

# Initialize all flags
UNBALANCED_FIXED=false
DUPLICATE_REMOVED=false
IC_ELIMINATED=false
CAPEX_RECLASSIFIED=false
TRIAL_BALANCE_MV_EXISTS=false
TRIAL_BALANCE_BALANCES=false
CONSOLIDATED_VW_EXISTS=false
CSV_EXISTS=false
CSV_SIZE=0
CSV_HAS_CATEGORIES=false
REMAINING_UNBALANCED=0
REMAINING_DUPLICATES=0
PENDING_IC_ELIMS=0

# --- Check if unbalanced JE was fixed ---
# JE-2024-0047 should have debits = credits after fix
UNBALANCED_CHECK=$(oracle_query_raw "SELECT ABS(SUM(debit_amount) - SUM(credit_amount)) FROM fiscal_admin.journal_lines WHERE entry_id = (SELECT entry_id FROM fiscal_admin.journal_entries WHERE entry_number = 'JE-2024-0047');" "system" | tr -d '[:space:]')
if [ "${UNBALANCED_CHECK:-5000}" = "0" ] 2>/dev/null || [ "${UNBALANCED_CHECK:-5000}" = "" ] 2>/dev/null; then
    UNBALANCED_FIXED=true
fi

# Count any remaining unbalanced entries
REMAINING_UNBALANCED=$(oracle_query_raw "SELECT COUNT(*) FROM (SELECT je.entry_id, ABS(SUM(jl.debit_amount) - SUM(jl.credit_amount)) AS diff FROM fiscal_admin.journal_entries je JOIN fiscal_admin.journal_lines jl ON je.entry_id = jl.entry_id GROUP BY je.entry_id HAVING ABS(SUM(jl.debit_amount) - SUM(jl.credit_amount)) > 0.01);" "system" | tr -d '[:space:]')
REMAINING_UNBALANCED=${REMAINING_UNBALANCED:-99}

# --- Check if duplicate JE was removed ---
DUP_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM fiscal_admin.journal_entries WHERE entry_number = 'JE-2024-0023-DUP';" "system" | tr -d '[:space:]')
if [ "${DUP_CHECK:-1}" = "0" ] 2>/dev/null; then
    DUPLICATE_REMOVED=true
fi

# Count remaining exact duplicates
REMAINING_DUPLICATES=$(oracle_query_raw "SELECT COUNT(*) FROM (SELECT entry_date, description, COUNT(*) AS cnt FROM fiscal_admin.journal_entries WHERE status = 'POSTED' GROUP BY entry_date, description HAVING COUNT(*) > 1);" "system" | tr -d '[:space:]')
REMAINING_DUPLICATES=${REMAINING_DUPLICATES:-99}

# --- Check if intercompany elimination was done ---
# Count IC journal entries that do NOT have a matching elimination record with status='COMPLETED'
IC_UNELIMINATED=$(oracle_query_raw "SELECT COUNT(*) FROM fiscal_admin.journal_entries WHERE is_intercompany = 1 AND entry_id NOT IN (SELECT source_entry_id FROM fiscal_admin.intercompany_eliminations WHERE status = 'COMPLETED' UNION ALL SELECT target_entry_id FROM fiscal_admin.intercompany_eliminations WHERE status = 'COMPLETED');" "system" | tr -d '[:space:]')
IC_UNELIMINATED=${IC_UNELIMINATED:-99}
PENDING_IC_ELIMS=${IC_UNELIMINATED:-99}
if [ "${IC_UNELIMINATED:-99}" = "0" ] 2>/dev/null; then
    IC_ELIMINATED=true
fi

# --- Check if capex was reclassified ---
# The $25000 should now be on PP&E account, not Utilities Expense
MISCLASS_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM fiscal_admin.journal_lines jl JOIN fiscal_admin.chart_of_accounts coa ON jl.account_id = coa.account_id WHERE jl.entry_id = (SELECT entry_id FROM fiscal_admin.journal_entries WHERE entry_number = 'JE-2024-0055') AND coa.account_name LIKE '%Utilities%' AND jl.debit_amount = 25000;" "system" | tr -d '[:space:]')
if [ "${MISCLASS_CHECK:-1}" = "0" ] 2>/dev/null; then
    CAPEX_RECLASSIFIED=true
fi

# Also check if PP&E now has the $25000 debit
PPE_HAS_ENTRY=$(oracle_query_raw "SELECT COUNT(*) FROM fiscal_admin.journal_lines jl JOIN fiscal_admin.chart_of_accounts coa ON jl.account_id = coa.account_id WHERE jl.entry_id = (SELECT entry_id FROM fiscal_admin.journal_entries WHERE entry_number = 'JE-2024-0055') AND coa.account_category = 'Assets' AND coa.account_name LIKE '%Property%' AND jl.debit_amount >= 25000;" "system" | tr -d '[:space:]')
PPE_HAS_ENTRY=${PPE_HAS_ENTRY:-0}

# --- Check materialized view TRIAL_BALANCE_MV ---
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'FISCAL_ADMIN' AND mview_name = 'TRIAL_BALANCE_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    TRIAL_BALANCE_MV_EXISTS=true

    # Check if the trial balance actually balances (total debits = total credits)
    BALANCE_DIFF=$(oracle_query_raw "SELECT ABS(SUM(DEBIT_BALANCE) - SUM(CREDIT_BALANCE)) FROM fiscal_admin.trial_balance_mv;" "system" | tr -d '[:space:]')
    if [ "${BALANCE_DIFF:-99999}" = "0" ] 2>/dev/null || [ "$(echo "${BALANCE_DIFF:-99999} < 0.02" | bc -l 2>/dev/null)" = "1" ]; then
        TRIAL_BALANCE_BALANCES=true
    fi
fi

# Also check for TRIAL_BALANCE_VW as alternate name
MV_CHECK_ALT=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'FISCAL_ADMIN' AND mview_name = 'TRIAL_BALANCE_VW';" "system" | tr -d '[:space:]')
MV_ALT_EXISTS=${MV_CHECK_ALT:-0}

# --- Check CONSOLIDATED_REPORT_VW ---
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'FISCAL_ADMIN' AND view_name = 'CONSOLIDATED_REPORT_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    CONSOLIDATED_VW_EXISTS=true
fi

# --- Check CSV export ---
CSV_PATH="/home/ga/fiscal_close_results.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(wc -c < "$CSV_PATH" 2>/dev/null)
    CSV_SIZE=${CSV_SIZE:-0}

    if grep -qiE "Assets|Liabilities|Equity|Revenue|Expenses" "$CSV_PATH" 2>/dev/null; then
        CSV_HAS_CATEGORIES=true
    fi
fi

# --- Check for ROLLUP usage in the MV definition ---
ROLLUP_USED=false
MV_TEXT=$(oracle_query_raw "SELECT query FROM all_mviews WHERE owner = 'FISCAL_ADMIN' AND mview_name IN ('TRIAL_BALANCE_MV','TRIAL_BALANCE_VW');" "system" 2>/dev/null)
if echo "$MV_TEXT" | grep -qiE "ROLLUP|CUBE" 2>/dev/null; then
    ROLLUP_USED=true
fi

# --- Collect GUI evidence ---
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# Sanitize all numeric variables before JSON output
REMAINING_UNBALANCED=$(sanitize_int "$REMAINING_UNBALANCED" 99)
REMAINING_DUPLICATES=$(sanitize_int "$REMAINING_DUPLICATES" 99)
PENDING_IC_ELIMS=$(sanitize_int "$PENDING_IC_ELIMS" 99)
PPE_HAS_ENTRY=$(sanitize_int "$PPE_HAS_ENTRY" 0)
CSV_SIZE=$(sanitize_int "$CSV_SIZE" 0)
MV_ALT_EXISTS=$(sanitize_int "$MV_ALT_EXISTS" 0)

# --- Write result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "unbalanced_je_fixed": $UNBALANCED_FIXED,
    "remaining_unbalanced_count": ${REMAINING_UNBALANCED:-99},
    "duplicate_je_removed": $DUPLICATE_REMOVED,
    "remaining_duplicate_count": ${REMAINING_DUPLICATES:-99},
    "intercompany_eliminated": $IC_ELIMINATED,
    "pending_ic_eliminations": ${PENDING_IC_ELIMS:-99},
    "capex_reclassified": $CAPEX_RECLASSIFIED,
    "ppe_has_entry": ${PPE_HAS_ENTRY:-0},
    "trial_balance_mv_exists": $TRIAL_BALANCE_MV_EXISTS,
    "trial_balance_mv_alt_exists": ${MV_ALT_EXISTS:-0},
    "trial_balance_balances": $TRIAL_BALANCE_BALANCES,
    "rollup_used": $ROLLUP_USED,
    "consolidated_vw_exists": $CONSOLIDATED_VW_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_size": ${CSV_SIZE:-0},
    "csv_has_categories": $CSV_HAS_CATEGORIES,
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/fiscal_close_result.json 2>/dev/null || sudo rm -f /tmp/fiscal_close_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/fiscal_close_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/fiscal_close_result.json
chmod 666 /tmp/fiscal_close_result.json 2>/dev/null || sudo chmod 666 /tmp/fiscal_close_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/fiscal_close_result.json"
cat /tmp/fiscal_close_result.json
echo "=== Export complete ==="
