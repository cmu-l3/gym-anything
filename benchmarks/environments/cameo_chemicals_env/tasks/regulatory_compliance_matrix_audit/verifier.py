#!/usr/bin/env python3
import json
import os
import csv
import io
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_regulatory_compliance_matrix_audit(traj, env_info, task_info):
    """
    Verifies the Regulatory Compliance Matrix Audit task.
    
    Criteria:
    1. CSV file exists and was created during the task.
    2. CSV has correct headers.
    3. Rows match the expected ground truth for Chlorine, Acetone, Propane, Benzene, and Formaldehyde.
    """
    
    # 1. Setup and retrieve result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    
    # Define score components
    score = 0
    feedback_parts = []
    
    # Retrieve task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)

    # Check file existence and creation time
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'compliance_matrix.csv' was not found on Desktop."}
    
    if not result_data.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not modified during the task session (anti-gaming check failed)."}
    
    score += 10 # Base points for file creation
    feedback_parts.append("CSV file created.")

    # Retrieve the CSV content
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(result_data["output_path"], temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            csv_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read CSV file: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name): os.unlink(temp_csv.name)

    # Parse CSV
    try:
        reader = csv.DictReader(io.StringIO(csv_content))
        headers = reader.fieldnames
        rows = list(reader)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Invalid CSV format: {str(e)}"}

    # Verify Headers
    required_headers = [h.lower().strip() for h in metadata.get("required_headers", [])]
    if not headers:
         return {"passed": False, "score": score, "feedback": "CSV file is empty or missing headers."}
         
    actual_headers = [h.lower().strip() for h in headers]
    
    # Flexible header checking
    header_mapping = {} # Map 'chemical' -> 'Chemical', 'caa_112r' -> 'CAA_112r' etc.
    missing_headers = []
    
    for req in required_headers:
        found = False
        for act in actual_headers:
            if req == act:
                found = True
                break
        if not found:
            # Try fuzzy match if exact fails (e.g. "CAA 112r" vs "CAA_112r")
            for act in actual_headers:
                if req.replace('_', ' ') in act.replace('_', ' '):
                    found = True
                    break
        if not found:
            missing_headers.append(req)
    
    if missing_headers:
        feedback_parts.append(f"Missing headers: {', '.join(missing_headers)}")
    else:
        score += 10
        feedback_parts.append("Headers correct.")

    # Normalize rows for lookup (Key by chemical name)
    agent_data = {}
    for row in rows:
        # Find chemical name column
        chem_name = None
        for k, v in row.items():
            if 'chemical' in k.lower():
                chem_name = v.strip().lower()
                break
        
        if chem_name:
            # Extract Yes/No flags
            flags = []
            # We look for columns matching our expected regulations
            # Order in ground truth: CAA, CWA, EPCRA
            
            # Helper to find value in row keys
            def find_val(keywords):
                for k, v in row.items():
                    if all(kw in k.lower() for kw in keywords):
                        return v.strip().upper()
                return "MISSING"

            caa = find_val(['caa', '112'])
            cwa = find_val(['cwa', '311'])
            epcra = find_val(['epcra', '313'])
            
            agent_data[chem_name] = [caa, cwa, epcra]

    # Verify Data against Ground Truth
    chemicals_checked = 0
    total_chemicals = len(ground_truth)
    
    # Ground truth mapping handles partial matches for chemical names
    # Chlorine, Acetone, Propane, Benzene, Formaldehyde
    
    points_per_chemical = 80.0 / total_chemicals # Distribute remaining 80 points
    
    for gt_chem, gt_flags in ground_truth.items():
        # Find matching row in agent data
        match_found = False
        agent_flags = None
        
        for ag_chem, ag_vals in agent_data.items():
            if gt_chem.lower() in ag_chem: # e.g. "formaldehyde" in "formaldehyde (solution)"
                match_found = True
                agent_flags = ag_vals
                break
        
        if not match_found:
            feedback_parts.append(f"Missing row for {gt_chem}.")
            continue
            
        # Compare flags
        # gt_flags is [CAA, CWA, EPCRA]
        # agent_flags is [CAA, CWA, EPCRA]
        
        chem_score = 0
        chem_errors = []
        
        # CAA 112r Check
        if normalize_bool(agent_flags[0]) == normalize_bool(gt_flags[0]):
            chem_score += (points_per_chemical / 3)
        else:
            chem_errors.append(f"CAA 112r (expected {gt_flags[0]})")

        # CWA 311 Check
        if normalize_bool(agent_flags[1]) == normalize_bool(gt_flags[1]):
            chem_score += (points_per_chemical / 3)
        else:
            chem_errors.append(f"CWA 311 (expected {gt_flags[1]})")

        # EPCRA 313 Check
        if normalize_bool(agent_flags[2]) == normalize_bool(gt_flags[2]):
            chem_score += (points_per_chemical / 3)
        else:
            chem_errors.append(f"EPCRA 313 (expected {gt_flags[2]})")

        score += chem_score
        
        if chem_errors:
            feedback_parts.append(f"{gt_chem}: Incorrect {', '.join(chem_errors)}")
        else:
            # feedback_parts.append(f"{gt_chem}: Correct") # Optional: too verbose
            pass

    score = min(100, int(score))
    
    # Pass threshold
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }

def normalize_bool(val):
    """Normalize YES/NO/TRUE/FALSE strings to standard boolean repr."""
    if not val: return None
    v = val.strip().lower()
    if v in ['yes', 'y', 'true', 't', 'x']: return True
    if v in ['no', 'n', 'false', 'f']: return False
    return None