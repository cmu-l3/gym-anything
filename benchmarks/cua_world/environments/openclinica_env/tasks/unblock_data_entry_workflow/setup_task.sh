#!/bin/bash
echo "=== Setting up unblock_data_entry_workflow task ==="

source /workspace/scripts/task_utils.sh

# 1. Resolve Study ID
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Ensure subject DM-105 exists
DM105_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE label = 'DM-105' AND study_id = $DM_STUDY_ID")
if [ "$DM105_EXISTS" = "0" ] || [ -z "$DM105_EXISTS" ]; then
    echo "Creating subject DM-105..."
    oc_query "INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created) VALUES ('1980-01-01', 'm', 1, 1, NOW())"
    SUBJ_ID=$(oc_query "SELECT subject_id FROM subject ORDER BY subject_id DESC LIMIT 1")
    oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, enrollment_date, owner_id, date_created) VALUES ('DM-105', $SUBJ_ID, $DM_STUDY_ID, 1, NOW(), 1, NOW())"
    echo "Subject DM-105 created."
fi

# 3. Inject the hard-blocking Rule into the DB
echo "Injecting SYS_BP_MAX_160 rule..."
# Clean up if it already exists to ensure a fresh state
EXISTING_RULE=$(oc_query "SELECT rule_id FROM rule WHERE name = 'SYS_BP_MAX_160' LIMIT 1")
if [ -n "$EXISTING_RULE" ]; then
    oc_query "DELETE FROM rule_set_rule WHERE rule_id = $EXISTING_RULE" 2>/dev/null || true
    oc_query "DELETE FROM rule WHERE rule_id = $EXISTING_RULE" 2>/dev/null || true
fi

oc_query "
DO \$\$
DECLARE
    v_rule_expr_id INT;
    v_target_expr_id INT;
    v_rule_id INT;
    v_rule_set_id INT;
BEGIN
    -- Target expression (the item the rule is assigned to)
    INSERT INTO rule_expression (value, context) VALUES ('SE_DM_BASE.F_VITAL_SIGNS.IG_VITAL_SIGNS.I_VITAL_SYSTOLIC', 'ItemData') RETURNING rule_expression_id INTO v_target_expr_id;
    
    -- Rule expression (the validation logic)
    INSERT INTO rule_expression (value, context) VALUES ('I_VITAL_SYSTOLIC le 160', 'ItemData') RETURNING rule_expression_id INTO v_rule_expr_id;
    
    -- Create Rule
    INSERT INTO rule (name, description, oc_oid, rule_expression_id, status_id, owner_id, date_created) 
    VALUES ('SYS_BP_MAX_160', 'Systolic BP cannot exceed 160', 'R_SYS_BP_MAX_160', v_rule_expr_id, 1, 1, NOW()) RETURNING rule_id INTO v_rule_id;
    
    -- Create Rule Set (Assignment to study)
    INSERT INTO rule_set (target_id, study_id, status_id, owner_id, date_created) 
    VALUES (v_target_expr_id, $DM_STUDY_ID, 1, 1, NOW()) RETURNING rule_set_id INTO v_rule_set_id;
    
    -- Map Rule to Rule Set (Active)
    INSERT INTO rule_set_rule (rule_set_id, rule_id, status_id, owner_id, date_created) 
    VALUES (v_rule_set_id, v_rule_id, 1, 1, NOW());
END \$\$;
"
echo "Rule SYS_BP_MAX_160 successfully injected."

# 4. Copy CRF template to a convenient location just in case agent needs to upload it
if [ -f "/workspace/data/sample_crf.xls" ]; then
    cp /workspace/data/sample_crf.xls /home/ga/vital_signs_crf.xls
    chown ga:ga /home/ga/vital_signs_crf.xls
fi

# 5. Record Initial State and Timestamps
date +%s > /tmp/task_start_time.txt
AUDIT_BASELINE=$(get_recent_audit_count 10)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count

# 6. Launch Firefox and establish session
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="