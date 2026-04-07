#!/usr/bin/env python3
"""
Verifier for create_clinical_stored_procedures task.

Verifies:
1. Existence of 4 MySQL stored routines.
2. Correct execution and output of each routine (tested against ground truth).
3. Creation and content of the demo text file.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_clinical_stored_procedures(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Parse Data
    routines = result.get('routines_list', [])
    if isinstance(routines, str):
        # Handle cases where SQL extraction might have failed or returned empty string
        try:
            routines = json.loads(routines) if routines else []
        except:
            routines = []

    routine_names = {r['name'].lower(): r['type'] for r in routines}
    exec_results = result.get('execution_results', {})
    demo_file = result.get('demo_file', {})

    # =========================================================
    # CRITERION 1: ROUTINE EXISTENCE (30 pts)
    # =========================================================
    # fn_patient_age (Function) - 7.5 pts
    if 'fn_patient_age' in routine_names and routine_names['fn_patient_age'] == 'FUNCTION':
        score += 7.5
        feedback_parts.append("fn_patient_age exists")
    else:
        feedback_parts.append("fn_patient_age MISSING")

    # sp_search_patients (Procedure) - 7.5 pts
    if 'sp_search_patients' in routine_names and routine_names['sp_search_patients'] == 'PROCEDURE':
        score += 7.5
        feedback_parts.append("sp_search_patients exists")
    else:
        feedback_parts.append("sp_search_patients MISSING")

    # sp_age_pyramid (Procedure) - 7.5 pts
    if 'sp_age_pyramid' in routine_names and routine_names['sp_age_pyramid'] == 'PROCEDURE':
        score += 7.5
        feedback_parts.append("sp_age_pyramid exists")
    else:
        feedback_parts.append("sp_age_pyramid MISSING")

    # sp_practice_summary (Procedure) - 7.5 pts
    if 'sp_practice_summary' in routine_names and routine_names['sp_practice_summary'] == 'PROCEDURE':
        score += 7.5
        feedback_parts.append("sp_practice_summary exists")
    else:
        feedback_parts.append("sp_practice_summary MISSING")

    # =========================================================
    # CRITERION 2: FUNCTIONAL CORRECTNESS (40 pts)
    # =========================================================
    
    # 1. fn_patient_age works (10 pts)
    age_out = str(exec_results.get('fn_patient_age', {}).get('output', 'ERROR'))
    age_exp = str(exec_results.get('fn_patient_age', {}).get('expected', ''))
    
    if age_out != 'ERROR' and age_out == age_exp and age_out.isdigit():
        score += 10
        feedback_parts.append(f"fn_patient_age correct ({age_out})")
    elif age_out != 'ERROR':
        feedback_parts.append(f"fn_patient_age incorrect (got {age_out}, expected {age_exp})")
    else:
        feedback_parts.append("fn_patient_age execution failed")

    # 2. sp_search_patients works (10 pts)
    search_b64 = exec_results.get('sp_search_patients', {}).get('output_b64', '')
    if search_b64 and search_b64 != 'ERROR':
        try:
            search_out = base64.b64decode(search_b64).decode('utf-8')
            # Check for header columns and data
            if "TESTER" in search_out and "GUID" in search_out:
                score += 10
                feedback_parts.append("sp_search_patients returned valid results")
            else:
                score += 5 # Partial credit if runs but output dubious
                feedback_parts.append("sp_search_patients ran but output format mismatch")
        except:
            feedback_parts.append("sp_search_patients output decode failed")
    else:
        feedback_parts.append("sp_search_patients execution failed")

    # 3. sp_age_pyramid works (10 pts)
    pyramid_b64 = exec_results.get('sp_age_pyramid', {}).get('output_b64', '')
    if pyramid_b64 and pyramid_b64 != 'ERROR':
        try:
            pyramid_out = base64.b64decode(pyramid_b64).decode('utf-8')
            # Look for headers or expected data format (AgeBracket, Gender)
            if "Age" in pyramid_out and ("Gender" in pyramid_out or "Sexe" in pyramid_out):
                score += 10
                feedback_parts.append("sp_age_pyramid output valid")
            else:
                score += 5
                feedback_parts.append("sp_age_pyramid ran but headers missing")
        except:
            feedback_parts.append("sp_age_pyramid decode failed")
    else:
        feedback_parts.append("sp_age_pyramid execution failed")

    # 4. sp_practice_summary works (10 pts)
    summary_b64 = exec_results.get('sp_practice_summary', {}).get('output_b64', '')
    gt_csv = exec_results.get('sp_practice_summary', {}).get('ground_truth_csv', '')
    
    if summary_b64 and summary_b64 != 'ERROR':
        try:
            summary_out = base64.b64decode(summary_b64).decode('utf-8')
            # Check if output contains the ground truth counts
            # GT format: Total,Male,Female (e.g., "105,45,60")
            gt_parts = gt_csv.split(',') if gt_csv else []
            
            matches = 0
            for val in gt_parts:
                if val and val in summary_out:
                    matches += 1
            
            if matches >= 2: # At least 2 of the metrics match exactly
                score += 10
                feedback_parts.append("sp_practice_summary metrics match GT")
            elif "Total" in summary_out or "Avg" in summary_out:
                score += 5
                feedback_parts.append("sp_practice_summary ran but metrics mismatch")
            else:
                feedback_parts.append("sp_practice_summary output unrecognized")
        except:
            feedback_parts.append("sp_practice_summary decode failed")
    else:
        feedback_parts.append("sp_practice_summary execution failed")

    # =========================================================
    # CRITERION 3: DEMO FILE (30 pts)
    # =========================================================
    if demo_file.get('exists'):
        score += 10
        feedback_parts.append("Demo file exists")
        
        if demo_file.get('created_during_task'):
            score += 5
            feedback_parts.append("Demo file created during task")
        
        content_b64 = demo_file.get('content_b64', '')
        if content_b64:
            try:
                content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
                
                # Check for content richness
                criteria_met = 0
                if "sp_search_patients" in content: criteria_met += 1
                if "sp_age_pyramid" in content: criteria_met += 1
                if "sp_practice_summary" in content: criteria_met += 1
                if "fn_patient_age" in content: criteria_met += 1
                
                if criteria_met >= 3:
                    score += 15
                    feedback_parts.append("Demo file content comprehensive")
                elif criteria_met >= 1:
                    score += 8
                    feedback_parts.append("Demo file content partial")
                else:
                    feedback_parts.append("Demo file missing routine names")
            except:
                feedback_parts.append("Demo file unreadable")
    else:
        feedback_parts.append("Demo file NOT found")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }