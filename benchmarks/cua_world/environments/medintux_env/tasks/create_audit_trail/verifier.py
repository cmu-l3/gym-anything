#!/usr/bin/env python3
"""
Verifier for create_audit_trail task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_audit_trail(traj, env_info, task_info):
    """
    Verify the MySQL audit trail system.
    
    Criteria:
    1. 'patient_audit_log' table exists with correct schema.
    2. All 6 required triggers exist.
    3. The agent's test data (AUDIT-TEST-001) appears in the log.
    4. The functional test (performed by export_result.sh) passed.
    5. The report file was generated.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    required_triggers = set(metadata.get('required_triggers', []))
    test_guid = metadata.get('test_guid', 'AUDIT-TEST-001')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Table Schema (20 points)
    # Check if table description contains expected columns
    schema_out = result.get('table_schema_output', '')
    required_cols = ['audit_id', 'operation_type', 'table_name', 'record_id', 'old_values', 'new_values']
    
    if "MISSING" in schema_out:
        feedback_parts.append("Audit table missing")
    else:
        cols_found = 0
        for col in required_cols:
            if col in schema_out:
                cols_found += 1
        
        if cols_found == len(required_cols):
            score += 20
            feedback_parts.append("Audit table schema correct")
        else:
            score += int((cols_found / len(required_cols)) * 20)
            feedback_parts.append(f"Audit table incomplete ({cols_found}/{len(required_cols)} columns)")

    # 2. Verify Triggers (30 points)
    # 5 points per trigger
    triggers_found = set(result.get('triggers_found', []))
    triggers_matched = required_triggers.intersection(triggers_found)
    
    trigger_score = len(triggers_matched) * 5
    score += trigger_score
    
    if len(triggers_matched) == len(required_triggers):
        feedback_parts.append("All triggers found")
    else:
        missing = required_triggers - triggers_found
        feedback_parts.append(f"Missing triggers: {', '.join(missing)}")

    # 3. Verify Agent's Test Data in Log (20 points)
    # Check if log content sample contains the test GUID
    log_sample = result.get('log_content_sample', '')
    if test_guid in log_sample:
        score += 20
        feedback_parts.append("Test patient audit entries found")
    else:
        feedback_parts.append("Test patient audit entries NOT found")

    # 4. Verify Functional Test (20 points)
    # Did the export script successfully trigger an audit log entry?
    if result.get('functional_test_passed', False):
        score += 20
        feedback_parts.append("Functional verification passed (triggers active)")
    else:
        feedback_parts.append("Functional verification failed (triggers inactive or broken)")

    # 5. Verify Report File (10 points)
    if result.get('report_exists', False) and result.get('report_size', 0) > 10:
        score += 10
        feedback_parts.append("Report file created")
    else:
        feedback_parts.append("Report file missing or empty")

    # Final Evaluation
    passed = score >= 60 and result.get('functional_test_passed', False) and ("MISSING" not in schema_out)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }