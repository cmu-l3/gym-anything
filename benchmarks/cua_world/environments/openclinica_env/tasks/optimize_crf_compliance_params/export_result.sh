#!/bin/bash
echo "=== Exporting optimize_crf_compliance_params result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Safety Follow-up' AND status_id != 3 LIMIT 1")

AE_PWD="false"
LAB_DDE="false"
QOL_REQ="true"

if [ -n "$SED_ID" ]; then
    # Extract Adverse Events parameters
    CRF_AE=$(oc_query "SELECT crf_id FROM crf WHERE name = 'Adverse Events' AND status_id != 3 LIMIT 1")
    if [ -n "$CRF_AE" ]; then
        EDC_AE=$(oc_query "SELECT electronic_signature FROM event_definition_crf WHERE study_event_definition_id = $SED_ID AND crf_id = $CRF_AE LIMIT 1" 2>/dev/null)
        if [ -z "$EDC_AE" ] || echo "$EDC_AE" | grep -qi "error"; then
            EDC_AE=$(oc_query "SELECT require_pwd FROM event_definition_crf WHERE study_event_definition_id = $SED_ID AND crf_id = $CRF_AE LIMIT 1" 2>/dev/null)
        fi
        AE_PWD=$(echo "$EDC_AE" | tr -d ' ')
    fi

    # Extract Lab Results parameters
    CRF_LAB=$(oc_query "SELECT crf_id FROM crf WHERE name = 'Lab Results' AND status_id != 3 LIMIT 1")
    if [ -n "$CRF_LAB" ]; then
        EDC_LAB=$(oc_query "SELECT double_entry FROM event_definition_crf WHERE study_event_definition_id = $SED_ID AND crf_id = $CRF_LAB LIMIT 1" 2>/dev/null)
        LAB_DDE=$(echo "$EDC_LAB" | tr -d ' ')
    fi

    # Extract Quality of Life parameters
    CRF_QOL=$(oc_query "SELECT crf_id FROM crf WHERE name = 'Quality of Life' AND status_id != 3 LIMIT 1")
    if [ -n "$CRF_QOL" ]; then
        EDC_QOL=$(oc_query "SELECT required_crf FROM event_definition_crf WHERE study_event_definition_id = $SED_ID AND crf_id = $CRF_QOL LIMIT 1" 2>/dev/null)
        QOL_REQ=$(echo "$EDC_QOL" | tr -d ' ')
    fi
fi

# Gather audit log metrics
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# Write out JSON result
TEMP_JSON=$(mktemp /tmp/crf_params_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "ae_pwd": "$(json_escape "$AE_PWD")",
    "lab_dde": "$(json_escape "$LAB_DDE")",
    "qol_req": "$(json_escape "$QOL_REQ")",
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null)"
}
EOF

# Resolve permissions safely
rm -f /tmp/crf_params_result.json 2>/dev/null || sudo rm -f /tmp/crf_params_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/crf_params_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/crf_params_result.json
chmod 666 /tmp/crf_params_result.json 2>/dev/null || sudo chmod 666 /tmp/crf_params_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/crf_params_result.json"
cat /tmp/crf_params_result.json
echo "=== Export complete ==="