#!/bin/bash
echo "=== Exporting VAR Analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

# Paths
SELECTION_CSV="/home/ga/RProjects/output/var_selection.csv"
DIAG_CSV="/home/ga/RProjects/output/var_diagnostics.csv"
IRF_PNG="/home/ga/RProjects/output/irf_wage_unemployment.png"
SCRIPT="/home/ga/RProjects/var_analysis.R"

# 1. Check Selection CSV
SEL_EXISTS=false
SEL_NEW=false
SEL_ROWS=0
if [ -f "$SELECTION_CSV" ]; then
    SEL_EXISTS=true
    MTIME=$(stat -c %Y "$SELECTION_CSV")
    [ "$MTIME" -gt "$TASK_START" ] && SEL_NEW=true
    SEL_ROWS=$(wc -l < "$SELECTION_CSV")
fi

# 2. Check Diagnostics CSV
DIAG_EXISTS=false
DIAG_NEW=false
HAS_PORTMANTEAU=false
HAS_GRANGER=false
if [ -f "$DIAG_CSV" ]; then
    DIAG_EXISTS=true
    MTIME=$(stat -c %Y "$DIAG_CSV")
    [ "$MTIME" -gt "$TASK_START" ] && DIAG_NEW=true
    # Check content roughly
    grep -qi "Portmanteau" "$DIAG_CSV" && HAS_PORTMANTEAU=true
    grep -qi "Granger" "$DIAG_CSV" && HAS_GRANGER=true
fi

# 3. Check IRF Plot
IRF_EXISTS=false
IRF_NEW=false
IRF_SIZE=0
if [ -f "$IRF_PNG" ]; then
    IRF_EXISTS=true
    MTIME=$(stat -c %Y "$IRF_PNG")
    [ "$MTIME" -gt "$TASK_START" ] && IRF_NEW=true
    IRF_SIZE=$(stat -c %s "$IRF_PNG")
fi

# 4. Check Script Content (for variable ordering)
SCRIPT_MODIFIED=false
HAS_VARS_PKG=false
HAS_CORRECT_ORDER=false
if [ -f "$SCRIPT" ]; then
    MTIME=$(stat -c %Y "$SCRIPT")
    [ "$MTIME" -gt "$TASK_START" ] && SCRIPT_MODIFIED=true
    CONTENT=$(cat "$SCRIPT")
    
    # Check for vars package loading
    echo "$CONTENT" | grep -qiE "library.*vars|require.*vars" && HAS_VARS_PKG=true
    
    # Check for ordering: "prod", "e", "U", "rw" 
    # This regex looks for the specific vector construction
    if echo "$CONTENT" | grep -qE 'c\s*\(\s*["'\'']prod["'\'']\s*,\s*["'\'']e["'\'']\s*,\s*["'\'']U["'\'']\s*,\s*["'\'']rw["'\'']\s*\)'; then
        HAS_CORRECT_ORDER=true
    # Also check if they selected columns by index or name in a data frame subset
    elif echo "$CONTENT" | grep -qE 'Canada\s*\[\s*,\s*c\s*\(\s*["'\'']prod["'\'']'; then
        HAS_CORRECT_ORDER=true
    fi
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "sel_exists": $SEL_EXISTS,
    "sel_new": $SEL_NEW,
    "sel_rows": $SEL_ROWS,
    "diag_exists": $DIAG_EXISTS,
    "diag_new": $DIAG_NEW,
    "has_portmanteau": $HAS_PORTMANTEAU,
    "has_granger": $HAS_GRANGER,
    "irf_exists": $IRF_EXISTS,
    "irf_new": $IRF_NEW,
    "irf_size": $IRF_SIZE,
    "script_modified": $SCRIPT_MODIFIED,
    "has_vars_pkg": $HAS_VARS_PKG,
    "has_correct_order": $HAS_CORRECT_ORDER
}
EOF

# Move to safe location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"