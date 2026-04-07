#!/bin/bash
# Export script for quarterly_pipeline_reconciliation_with_ticket_crossref task
#
# Queries the final state of all target deals and the report existence,
# then writes a structured JSON for verification.

echo "=== Exporting quarterly_pipeline_reconciliation results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/reconciliation_final.png

TASK_START=$(cat /tmp/reconciliation_start_ts 2>/dev/null || echo "0")

# ---------------------------------------------------------------
# Query each target deal: stage, probability, and whether the
# description contains the [Q1-AUDIT] tag.
# Description is stored in vtiger_crmentity.description (not vtiger_potential).
# ---------------------------------------------------------------

query_deal() {
    local deal_name="$1"
    local prefix="$2"

    local data
    data=$(vtiger_db_query "SELECT sales_stage, probability FROM vtiger_potential WHERE potentialname='$deal_name' LIMIT 1")
    local stage=$(echo "$data" | awk -F'\t' '{print $1}')
    local prob=$(echo "$data" | awk -F'\t' '{print $2}')

    # Check for [Q1-AUDIT] tag in description via SQL JOIN with vtiger_crmentity
    local has_tag
    has_tag=$(vtiger_db_query "SELECT CASE WHEN ce.description LIKE '%Q1-AUDIT%' THEN 1 ELSE 0 END FROM vtiger_potential p JOIN vtiger_crmentity ce ON p.potentialid=ce.crmid WHERE p.potentialname='$deal_name' LIMIT 1" | tr -d '[:space:]')

    # Check for specific tag variants
    local has_auto_closed
    has_auto_closed=$(vtiger_db_query "SELECT CASE WHEN ce.description LIKE '%Q1-AUDIT%Auto-closed%' THEN 1 ELSE 0 END FROM vtiger_potential p JOIN vtiger_crmentity ce ON p.potentialid=ce.crmid WHERE p.potentialname='$deal_name' LIMIT 1" | tr -d '[:space:]')
    local has_held
    has_held=$(vtiger_db_query "SELECT CASE WHEN ce.description LIKE '%Q1-AUDIT%Held%' THEN 1 ELSE 0 END FROM vtiger_potential p JOIN vtiger_crmentity ce ON p.potentialid=ce.crmid WHERE p.potentialname='$deal_name' LIMIT 1" | tr -d '[:space:]')
    local has_risk_adjusted
    has_risk_adjusted=$(vtiger_db_query "SELECT CASE WHEN ce.description LIKE '%Q1-AUDIT%Risk-adjusted%' THEN 1 ELSE 0 END FROM vtiger_potential p JOIN vtiger_crmentity ce ON p.potentialid=ce.crmid WHERE p.potentialname='$deal_name' LIMIT 1" | tr -d '[:space:]')

    # Export as env vars with the given prefix
    eval "${prefix}_STAGE=\"$stage\""
    eval "${prefix}_PROB=\"$prob\""
    eval "${prefix}_HAS_TAG=\"${has_tag:-0}\""
    eval "${prefix}_HAS_AUTO_CLOSED=\"${has_auto_closed:-0}\""
    eval "${prefix}_HAS_HELD=\"${has_held:-0}\""
    eval "${prefix}_HAS_RISK_ADJ=\"${has_risk_adjusted:-0}\""
}

echo "Querying deal states..."

# Rule 1 targets (past-due)
query_deal "BrightPath LMS Platform Build" "BRIGHTPATH"
query_deal "Catalyst LIMS Implementation" "CATALYST"

# Rule 2 targets (critical ticket orgs)
query_deal "Atlas Supply Chain Analytics" "ATLAS"
query_deal "Pinnacle EHR Security Upgrade" "PINNACLE"

# Rule 3 targets (major ticket orgs)
query_deal "GreenLeaf IoT Factory Monitoring" "GREENLEAF"
query_deal "Sterling Trading Platform Modernization" "STERLING"

# Clean deals (should be unchanged)
query_deal "Apex Cloud Migration Phase 2" "APEX"
query_deal "Horizon 5G Network Planning" "HORIZON"
query_deal "Coastal Retail E-Commerce Replatform" "COASTAL"
query_deal "Ironclad Claims AI Platform" "IRONCLAD"

# ---------------------------------------------------------------
# Check report existence
# ---------------------------------------------------------------
REPORT_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_report WHERE reportname LIKE '%Q1 2026%Pipeline%Reconciliation%'" | tr -d '[:space:]')

# ---------------------------------------------------------------
# Load baselines for clean deal comparison
# ---------------------------------------------------------------
BASELINES=$(cat /tmp/reconciliation_baselines.json 2>/dev/null || echo '{}')

# ---------------------------------------------------------------
# Write result JSON
# ---------------------------------------------------------------
python3 << PYEOF
import json

result = {
    # Rule 1: Past-due deals — expected: Closed Lost / 0% / Auto-closed tag
    "brightpath_stage": "${BRIGHTPATH_STAGE:-}".strip(),
    "brightpath_probability": "${BRIGHTPATH_PROB:-}".strip(),
    "brightpath_has_audit_tag": int("${BRIGHTPATH_HAS_TAG:-0}" or "0"),
    "brightpath_has_auto_closed_tag": int("${BRIGHTPATH_HAS_AUTO_CLOSED:-0}" or "0"),

    "catalyst_stage": "${CATALYST_STAGE:-}".strip(),
    "catalyst_probability": "${CATALYST_PROB:-}".strip(),
    "catalyst_has_audit_tag": int("${CATALYST_HAS_TAG:-0}" or "0"),
    "catalyst_has_auto_closed_tag": int("${CATALYST_HAS_AUTO_CLOSED:-0}" or "0"),

    # Rule 2: Critical ticket deals — expected: Needs Analysis / 10% / Held tag
    "atlas_stage": "${ATLAS_STAGE:-}".strip(),
    "atlas_probability": "${ATLAS_PROB:-}".strip(),
    "atlas_has_audit_tag": int("${ATLAS_HAS_TAG:-0}" or "0"),
    "atlas_has_held_tag": int("${ATLAS_HAS_HELD:-0}" or "0"),

    "pinnacle_stage": "${PINNACLE_STAGE:-}".strip(),
    "pinnacle_probability": "${PINNACLE_PROB:-}".strip(),
    "pinnacle_has_audit_tag": int("${PINNACLE_HAS_TAG:-0}" or "0"),
    "pinnacle_has_held_tag": int("${PINNACLE_HAS_HELD:-0}" or "0"),

    # Rule 3: Major ticket deals — expected: prob-20 / Risk-adjusted tag
    "greenleaf_stage": "${GREENLEAF_STAGE:-}".strip(),
    "greenleaf_probability": "${GREENLEAF_PROB:-}".strip(),
    "greenleaf_has_audit_tag": int("${GREENLEAF_HAS_TAG:-0}" or "0"),
    "greenleaf_has_risk_adj_tag": int("${GREENLEAF_HAS_RISK_ADJ:-0}" or "0"),

    "sterling_stage": "${STERLING_STAGE:-}".strip(),
    "sterling_probability": "${STERLING_PROB:-}".strip(),
    "sterling_has_audit_tag": int("${STERLING_HAS_TAG:-0}" or "0"),
    "sterling_has_risk_adj_tag": int("${STERLING_HAS_RISK_ADJ:-0}" or "0"),

    # Clean deals — expected: unchanged from baselines, no audit tags
    "apex_stage": "${APEX_STAGE:-}".strip(),
    "apex_probability": "${APEX_PROB:-}".strip(),
    "apex_has_audit_tag": int("${APEX_HAS_TAG:-0}" or "0"),

    "horizon_stage": "${HORIZON_STAGE:-}".strip(),
    "horizon_probability": "${HORIZON_PROB:-}".strip(),
    "horizon_has_audit_tag": int("${HORIZON_HAS_TAG:-0}" or "0"),

    "coastal_stage": "${COASTAL_STAGE:-}".strip(),
    "coastal_probability": "${COASTAL_PROB:-}".strip(),
    "coastal_has_audit_tag": int("${COASTAL_HAS_TAG:-0}" or "0"),

    "ironclad_stage": "${IRONCLAD_STAGE:-}".strip(),
    "ironclad_probability": "${IRONCLAD_PROB:-}".strip(),
    "ironclad_has_audit_tag": int("${IRONCLAD_HAS_TAG:-0}" or "0"),

    # Report
    "report_exists": int("${REPORT_COUNT:-0}" or "0"),

    # Baselines for clean deal verification
    "baselines": json.loads('''${BASELINES}'''),

    "task_start": ${TASK_START}
}

with open('/tmp/reconciliation_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
