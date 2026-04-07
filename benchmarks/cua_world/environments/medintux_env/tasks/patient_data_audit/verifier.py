#!/usr/bin/env python3
"""
Verifier for patient_data_audit task.
Compares agent's CSV output against ground truth generated from the database.
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_csv_file(file_path):
    """Parse CSV file into a list of dictionaries."""
    rows = []
    try:
        with open(file_path, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            # Normalize headers: strip whitespace, lowercase
            if reader.fieldnames:
                reader.fieldnames = [h.strip().lower() for h in reader.fieldnames]
            for row in reader:
                # clean keys and values
                clean_row = {k: v.strip() for k, v in row.items() if k}
                rows.append(clean_row)
    except Exception as e:
        logger.error(f"Error parsing CSV {file_path}: {e}")
        return None
    return rows

def verify_patient_data_audit(traj, env_info, task_info):
    """
    Verify the patient data audit CSV.
    
    Scoring:
    1. File exists & valid headers (25 pts)
    2. Test patients present (25 pts)
    3. Missing field flags correct (25 pts)
    4. Patient count matches ground truth (15 pts)
    5. No false positives (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Create temp files for artifacts
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_agent_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    temp_gt_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    
    try:
        # Copy files
        try:
            copy_from_env("/tmp/task_result.json", temp_result_json)
            with open(temp_result_json, 'r') as f:
                result_meta = json.load(f)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result metadata"}

        # Check basic file existence
        if not result_meta.get('file_exists', False):
            return {"passed": False, "score": 0, "feedback": "Output file audit_report.csv not found"}
            
        if not result_meta.get('created_during_task', False):
            feedback_parts.append("WARNING: File timestamp indicates it might pre-date the task")

        # Copy content files
        copy_from_env("/tmp/agent_report.csv", temp_agent_csv)
        copy_from_env("/tmp/ground_truth.csv", temp_gt_csv)
        
        # Parse files
        agent_data = parse_csv_file(temp_agent_csv)
        gt_data = parse_csv_file(temp_gt_csv)
        
        if agent_data is None:
            return {"passed": False, "score": 10, "feedback": "File exists but is not valid CSV"}
            
        if not agent_data:
            return {"passed": False, "score": 10, "feedback": "File exists but contains no data rows"}

        # Criterion 1: Headers (25 pts)
        expected_headers = {"last_name", "first_name", "dob_missing", "ssn_missing", "address_missing", "phone_missing"}
        agent_headers = set(agent_data[0].keys())
        
        # Allow some flexibility (case insensitive was handled in parser)
        if expected_headers.issubset(agent_headers):
            score += 25
            feedback_parts.append("Headers correct")
        else:
            missing_h = expected_headers - agent_headers
            feedback_parts.append(f"Missing headers: {missing_h}")
            score += 5 # Minimal credit for existing file
            
        # Helper to find patient in data
        def find_patient(data, last_name, first_name):
            for row in data:
                if (row.get('last_name', '').upper() == last_name.upper() and 
                    row.get('first_name', '').upper() == first_name.upper()):
                    return row
            return None

        # Criterion 2: Test Patients Presence (25 pts)
        test_patients = ["AUDIT_NODOB", "AUDIT_NOSS", "AUDIT_NOADDR", "AUDIT_MULTI"]
        found_count = 0
        for name in test_patients:
            # We assume first name logic based on setup script:
            # AUDIT_NODOB Pierre, AUDIT_NOSS Sophie, etc.
            # But searching just by last name is safer given unique names
            found = False
            for row in agent_data:
                if row.get('last_name', '').upper() == name:
                    found = True
                    break
            if found:
                found_count += 1
        
        presence_score = int((found_count / len(test_patients)) * 25)
        score += presence_score
        feedback_parts.append(f"Found {found_count}/{len(test_patients)} test patients")

        # Criterion 3: Flag Correctness (25 pts)
        # Expected flags mapping
        expected_flags = {
            "AUDIT_NODOB":  {"dob_missing": "1", "ssn_missing": "0", "address_missing": "0", "phone_missing": "0"},
            "AUDIT_NOSS":   {"dob_missing": "0", "ssn_missing": "1", "address_missing": "0", "phone_missing": "0"},
            "AUDIT_NOADDR": {"dob_missing": "0", "ssn_missing": "0", "address_missing": "1", "phone_missing": "0"},
            "AUDIT_MULTI":  {"dob_missing": "1", "ssn_missing": "0", "address_missing": "1", "phone_missing": "1"}
        }
        
        correct_flags_count = 0
        total_checks = 0
        
        for name, flags in expected_flags.items():
            patient = None
            for row in agent_data:
                if row.get('last_name', '').upper() == name:
                    patient = row
                    break
            
            if patient:
                # Check each flag
                patient_correct = True
                for field, val in flags.items():
                    # Handle flexible boolean representation (1/0, true/false)
                    agent_val = patient.get(field, '0')
                    if agent_val not in [val, str(val), 'true' if val=='1' else 'false']:
                        patient_correct = False
                
                if patient_correct:
                    correct_flags_count += 1
            total_checks += 1
            
        flag_score = int((correct_flags_count / total_checks) * 25) if total_checks > 0 else 0
        score += flag_score
        feedback_parts.append(f"Flags correct for {correct_flags_count}/{total_checks} patients")

        # Criterion 4: Count Matching (15 pts)
        gt_count = len(gt_data)
        agent_count = len(agent_data)
        
        # Tolerance +/- 2
        if abs(agent_count - gt_count) <= 2:
            score += 15
            feedback_parts.append(f"Patient count matches ground truth ({agent_count} vs {gt_count})")
        else:
            feedback_parts.append(f"Patient count mismatch (Agent: {agent_count}, GT: {gt_count})")

        # Criterion 5: False Positive (10 pts)
        # AUDIT_COMPLET should NOT be there
        fp_found = False
        for row in agent_data:
            if row.get('last_name', '').upper() == 'AUDIT_COMPLET':
                fp_found = True
                break
        
        if not fp_found:
            score += 10
            feedback_parts.append("No false positives")
        else:
            feedback_parts.append("False positive found (AUDIT_COMPLET)")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        for f in [temp_result_json, temp_agent_csv, temp_gt_csv]:
            if os.path.exists(f):
                os.unlink(f)

    passed = score >= 50
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }