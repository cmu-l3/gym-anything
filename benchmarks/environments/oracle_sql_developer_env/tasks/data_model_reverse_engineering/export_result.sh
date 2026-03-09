#!/bin/bash
echo "=== Exporting Data Model Reverse Engineering Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# -------------------------------------------------------
# Read baselines
# -------------------------------------------------------
INITIAL_TABLE_COMMENTS=$(cat /tmp/initial_legacy_table_comments 2>/dev/null || echo "0")
INITIAL_COL_COMMENTS=$(cat /tmp/initial_legacy_col_comments 2>/dev/null || echo "0")
INITIAL_PK_COUNT=$(cat /tmp/initial_legacy_pk_count 2>/dev/null || echo "0")
INITIAL_FK_COUNT=$(cat /tmp/initial_legacy_fk_count 2>/dev/null || echo "0")

# -------------------------------------------------------
# Current state: table comments
# -------------------------------------------------------
TABLE_COMMENT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_comments WHERE owner='LEGACY_OPS' AND comments IS NOT NULL AND TRIM(comments) != ''" "system")
NEW_TABLE_COMMENTS=$((${TABLE_COMMENT_COUNT:-0} - ${INITIAL_TABLE_COMMENTS:-0}))

# Get list of commented tables
COMMENTED_TABLES=$(oracle_query_raw "SELECT table_name FROM all_tab_comments WHERE owner='LEGACY_OPS' AND comments IS NOT NULL AND TRIM(comments) != '' ORDER BY table_name" "system")

# -------------------------------------------------------
# Current state: column comments
# -------------------------------------------------------
COL_COMMENT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_col_comments WHERE owner='LEGACY_OPS' AND comments IS NOT NULL AND TRIM(comments) != ''" "system")
NEW_COL_COMMENTS=$((${COL_COMMENT_COUNT:-0} - ${INITIAL_COL_COMMENTS:-0}))

# -------------------------------------------------------
# Check comments quality — sample a few to ensure non-generic
# -------------------------------------------------------
COMMENT_SAMPLE=$(oracle_query_raw "SELECT MIN(LENGTH(comments)) FROM all_tab_comments WHERE owner='LEGACY_OPS' AND comments IS NOT NULL AND TRIM(comments) != ''" "system")

# -------------------------------------------------------
# Primary key constraints
# -------------------------------------------------------
PK_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints WHERE owner='LEGACY_OPS' AND constraint_type='P'" "system")
NEW_PK_COUNT=$((${PK_COUNT:-0} - ${INITIAL_PK_COUNT:-0}))

# Check which tables have PKs
T_CLI_PK=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints WHERE owner='LEGACY_OPS' AND table_name='T_CLI' AND constraint_type='P'" "system")
T_ORD_PK=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints WHERE owner='LEGACY_OPS' AND table_name='T_ORD' AND constraint_type='P'" "system")
T_PRD_PK=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints WHERE owner='LEGACY_OPS' AND table_name='T_PRD' AND constraint_type='P'" "system")
T_CAT_PK=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints WHERE owner='LEGACY_OPS' AND table_name='T_CAT' AND constraint_type='P'" "system")
T_EMP_PK=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints WHERE owner='LEGACY_OPS' AND table_name='T_EMP' AND constraint_type='P'" "system")
T_DEPT_PK=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints WHERE owner='LEGACY_OPS' AND table_name='T_DEPT' AND constraint_type='P'" "system")

# -------------------------------------------------------
# Foreign key constraints
# -------------------------------------------------------
FK_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints WHERE owner='LEGACY_OPS' AND constraint_type='R'" "system")
NEW_FK_COUNT=$((${FK_COUNT:-0} - ${INITIAL_FK_COUNT:-0}))

# Check specific FK relationships
T_ORD_CLI_FK=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints c JOIN all_cons_columns cc ON c.constraint_name=cc.constraint_name AND c.owner=cc.owner WHERE c.owner='LEGACY_OPS' AND c.table_name='T_ORD' AND c.constraint_type='R' AND cc.column_name='CLI_ID'" "system")
T_ORD_EMP_FK=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints c JOIN all_cons_columns cc ON c.constraint_name=cc.constraint_name AND c.owner=cc.owner WHERE c.owner='LEGACY_OPS' AND c.table_name='T_ORD' AND c.constraint_type='R' AND cc.column_name='EMP_ID'" "system")
T_ORD_ITM_ORD_FK=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints c JOIN all_cons_columns cc ON c.constraint_name=cc.constraint_name AND c.owner=cc.owner WHERE c.owner='LEGACY_OPS' AND c.table_name='T_ORD_ITM' AND c.constraint_type='R' AND cc.column_name='ORD_ID'" "system")
T_ORD_ITM_PRD_FK=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints c JOIN all_cons_columns cc ON c.constraint_name=cc.constraint_name AND c.owner=cc.owner WHERE c.owner='LEGACY_OPS' AND c.table_name='T_ORD_ITM' AND c.constraint_type='R' AND cc.column_name='PRD_ID'" "system")
T_PRD_CAT_FK=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints c JOIN all_cons_columns cc ON c.constraint_name=cc.constraint_name AND c.owner=cc.owner WHERE c.owner='LEGACY_OPS' AND c.table_name='T_PRD' AND c.constraint_type='R' AND cc.column_name='CAT_ID'" "system")
T_EMP_DEPT_FK=$(oracle_query_raw "SELECT COUNT(*) FROM all_constraints c JOIN all_cons_columns cc ON c.constraint_name=cc.constraint_name AND c.owner=cc.owner WHERE c.owner='LEGACY_OPS' AND c.table_name='T_EMP' AND c.constraint_type='R' AND cc.column_name='DEPT_ID'" "system")

# -------------------------------------------------------
# Schema analysis report check
# -------------------------------------------------------
REPORT_FILE="/home/ga/Documents/exports/legacy_ops_analysis.txt"
REPORT_EXISTS=false
REPORT_SIZE=0
REPORT_MENTIONS_TABLE=false
REPORT_MENTIONS_RELATIONSHIP=false
REPORT_MEANINGFUL=false

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_SIZE=$(wc -c < "$REPORT_FILE")
    if grep -qi "T_CLI\|T_ORD\|T_PRD\|T_EMP\|T_DEPT\|clients\|orders\|products" "$REPORT_FILE"; then
        REPORT_MENTIONS_TABLE=true
    fi
    if grep -qi "foreign key\|relationship\|references\|FK\|join\|T_ORD_ITM" "$REPORT_FILE"; then
        REPORT_MENTIONS_RELATIONSHIP=true
    fi
    if [ "$REPORT_SIZE" -gt 500 ]; then
        REPORT_MEANINGFUL=true
    fi
fi

# -------------------------------------------------------
# Collect GUI evidence
# -------------------------------------------------------
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# -------------------------------------------------------
# Build result JSON
# -------------------------------------------------------
cat > /tmp/data_model_reverse_engineering_result.json << EOF
{
  "initial_table_comments": ${INITIAL_TABLE_COMMENTS:-0},
  "initial_col_comments": ${INITIAL_COL_COMMENTS:-0},
  "initial_pk_count": ${INITIAL_PK_COUNT:-0},
  "initial_fk_count": ${INITIAL_FK_COUNT:-0},

  "table_comment_count": ${TABLE_COMMENT_COUNT:-0},
  "new_table_comments": ${NEW_TABLE_COMMENTS:-0},
  "col_comment_count": ${COL_COMMENT_COUNT:-0},
  "new_col_comments": ${NEW_COL_COMMENTS:-0},
  "min_comment_length": ${COMMENT_SAMPLE:-0},

  "pk_count": ${PK_COUNT:-0},
  "new_pk_count": ${NEW_PK_COUNT:-0},
  "t_cli_pk": $([ "${T_CLI_PK:-0}" -gt 0 ] && echo true || echo false),
  "t_ord_pk": $([ "${T_ORD_PK:-0}" -gt 0 ] && echo true || echo false),
  "t_prd_pk": $([ "${T_PRD_PK:-0}" -gt 0 ] && echo true || echo false),
  "t_cat_pk": $([ "${T_CAT_PK:-0}" -gt 0 ] && echo true || echo false),
  "t_emp_pk": $([ "${T_EMP_PK:-0}" -gt 0 ] && echo true || echo false),
  "t_dept_pk": $([ "${T_DEPT_PK:-0}" -gt 0 ] && echo true || echo false),

  "fk_count": ${FK_COUNT:-0},
  "new_fk_count": ${NEW_FK_COUNT:-0},
  "t_ord_cli_fk": $([ "${T_ORD_CLI_FK:-0}" -gt 0 ] && echo true || echo false),
  "t_ord_emp_fk": $([ "${T_ORD_EMP_FK:-0}" -gt 0 ] && echo true || echo false),
  "t_ord_itm_ord_fk": $([ "${T_ORD_ITM_ORD_FK:-0}" -gt 0 ] && echo true || echo false),
  "t_ord_itm_prd_fk": $([ "${T_ORD_ITM_PRD_FK:-0}" -gt 0 ] && echo true || echo false),
  "t_prd_cat_fk": $([ "${T_PRD_CAT_FK:-0}" -gt 0 ] && echo true || echo false),
  "t_emp_dept_fk": $([ "${T_EMP_DEPT_FK:-0}" -gt 0 ] && echo true || echo false),

  "report_exists": $REPORT_EXISTS,
  "report_size": $REPORT_SIZE,
  "report_mentions_tables": $REPORT_MENTIONS_TABLE,
  "report_mentions_relationships": $REPORT_MENTIONS_RELATIONSHIP,
  "report_meaningful": $REPORT_MEANINGFUL,

  $GUI_EVIDENCE
}
EOF

chmod 666 /tmp/data_model_reverse_engineering_result.json
echo "=== Data Model Reverse Engineering Export Complete ==="
echo "Result saved to /tmp/data_model_reverse_engineering_result.json"
cat /tmp/data_model_reverse_engineering_result.json
