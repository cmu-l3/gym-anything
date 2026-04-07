#!/usr/bin/env python3
"""
Verifier for Patient Entity Resolution task.

Scoring:
- Table created with correct structure: 20 pts
- Exact match found (Case A): 10 pts
- Fuzzy match 'Typo' found (Case B): 25 pts
- Fuzzy match 'Format' found (Case C): 25 pts
- False positives avoided (Case D & E): 10 pts
- CSV Report exported: 10 pts

Pass Threshold: 70 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_patient_entity_resolution(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/patient_linkage_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Table Structure (20 pts)
    if result.get("table_exists", False):
        if result.get("columns_correct", False):
            score += 20
            feedback.append("Table PATIENT_LINKAGE created with correct columns (+20).")
        else:
            score += 10
            feedback.append("Table PATIENT_LINKAGE created but missing required columns (+10).")
    else:
        feedback.append("Table PATIENT_LINKAGE not found (0).")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Exact Match (10 pts)
    if result.get("match_a_found", False):
        score += 10
        feedback.append("Exact match (Jonathan Doe) found (+10).")
    else:
        feedback.append("Exact match missed.")

    # 3. Fuzzy Matches (50 pts)
    if result.get("match_b_found", False):
        score += 25
        feedback.append("Fuzzy match 'Typo' (Christopher Nolan) found (+25).")
    else:
        feedback.append("Fuzzy match 'Typo' missed.")

    if result.get("match_c_found", False):
        score += 25
        feedback.append("Fuzzy match 'Format' (Sarah O'Connor) found (+25).")
    else:
        feedback.append("Fuzzy match 'Format' missed.")

    # 4. False Positives (10 pts)
    # Case D (Bill Gates vs William Gates) is typically ~76 JaroWinkler, so <90. Should NOT match.
    # Case E (Michael Jordan) has diff DOB. Should NOT match.
    fp_score = 10
    if result.get("false_positive_d_found", False):
        fp_score -= 5
        feedback.append("False positive: Matched low-score pair (Bill Gates) (-5).")
    
    if result.get("false_positive_e_found", False):
        fp_score -= 5
        feedback.append("False positive: Matched different DOB pair (-5).")
        
    score += fp_score
    if fp_score == 10:
        feedback.append("No false positives found (+10).")

    # 5. CSV Export (10 pts)
    if result.get("csv_exists", False) and result.get("csv_row_count", 0) > 0:
        score += 10
        feedback.append("CSV report exported successfully (+10).")
    else:
        feedback.append("CSV report missing or empty.")

    # Adjustment: if total score > 100 (logic check), cap it.
    score = min(score, 100)
    
    # Requirement: Must find at least one fuzzy match to pass
    fuzzy_success = result.get("match_b_found", False) or result.get("match_c_found", False)
    passed = score >= 70 and fuzzy_success

    if not fuzzy_success:
        feedback.append("FAILED: Did not successfully identify fuzzy matches using UTL_MATCH.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }