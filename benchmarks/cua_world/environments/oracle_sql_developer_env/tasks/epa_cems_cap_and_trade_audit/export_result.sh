#!/bin/bash
echo "=== Exporting EPA Audit results ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

safe_query() {
    local val=$(oracle_query_raw "$1" "system" 2>/dev/null | head -1 | tr -d '[:space:]')
    if [[ "$val" == ERROR* ]] || [[ -z "$val" ]]; then
        echo "0"
    else
        echo "$val"
    fi
}

CEMS_IMPUTED_VW_EXISTS=$(safe_query "SELECT COUNT(*) FROM all_views WHERE owner='EPA_AUDIT' AND view_name='CEMS_IMPUTED_VW'")
ANNUAL_EMISSIONS_VW_EXISTS=$(safe_query "SELECT COUNT(*) FROM all_views WHERE owner='EPA_AUDIT' AND view_name='ANNUAL_EMISSIONS_VW'")
NET_ALLOWANCES_VW_EXISTS=$(safe_query "SELECT COUNT(*) FROM all_views WHERE owner='EPA_AUDIT' AND view_name='NET_ALLOWANCES_VW'")
COMPLIANCE_PENALTIES_EXISTS=$(safe_query "SELECT COUNT(*) FROM all_tables WHERE owner='EPA_AUDIT' AND table_name='COMPLIANCE_PENALTIES'")

IMPUTED_102_4=$(safe_query "SELECT imputed_co2 FROM epa_audit.cems_imputed_vw WHERE facility_id=102 AND op_hour=4")
IMPUTED_103_4=$(safe_query "SELECT imputed_co2 FROM epa_audit.cems_imputed_vw WHERE facility_id=103 AND op_hour=4")

EMISSIONS_103=$(safe_query "SELECT total_emissions_tons FROM epa_audit.annual_emissions_vw WHERE facility_id=103")

NET_ALLOWANCES_102=$(safe_query "SELECT final_allowances FROM epa_audit.net_allowances_vw WHERE facility_id=102")
NET_ALLOWANCES_103=$(safe_query "SELECT final_allowances FROM epa_audit.net_allowances_vw WHERE facility_id=103")
NET_ALLOWANCES_104=$(safe_query "SELECT final_allowances FROM epa_audit.net_allowances_vw WHERE facility_id=104")

PENALTY_COUNT=$(safe_query "SELECT COUNT(*) FROM epa_audit.compliance_penalties")
PENALTY_102=$(safe_query "SELECT penalty_amount FROM epa_audit.compliance_penalties WHERE facility_id=102")
PENALTY_103=$(safe_query "SELECT penalty_amount FROM epa_audit.compliance_penalties WHERE facility_id=103")
PENALTY_104=$(safe_query "SELECT penalty_amount FROM epa_audit.compliance_penalties WHERE facility_id=104")

CSV_EXISTS="false"
CSV_SIZE="0"
if [ -f "/home/ga/Documents/exports/epa_penalties.csv" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "/home/ga/Documents/exports/epa_penalties.csv")
fi

GUI_EVIDENCE=$(collect_gui_evidence || echo "\"gui_evidence\": {}")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "cems_imputed_vw_exists": $([ "$CEMS_IMPUTED_VW_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "annual_emissions_vw_exists": $([ "$ANNUAL_EMISSIONS_VW_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "net_allowances_vw_exists": $([ "$NET_ALLOWANCES_VW_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "compliance_penalties_exists": $([ "$COMPLIANCE_PENALTIES_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "imputed_102_4": $IMPUTED_102_4,
    "imputed_103_4": $IMPUTED_103_4,
    "emissions_103": $EMISSIONS_103,
    "net_allowances_102": $NET_ALLOWANCES_102,
    "net_allowances_103": $NET_ALLOWANCES_103,
    "net_allowances_104": $NET_ALLOWANCES_104,
    "penalty_count": $PENALTY_COUNT,
    "penalty_102": $PENALTY_102,
    "penalty_103": $PENALTY_103,
    "penalty_104": $PENALTY_104,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    $GUI_EVIDENCE
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
echo "Results exported to /tmp/task_result.json"