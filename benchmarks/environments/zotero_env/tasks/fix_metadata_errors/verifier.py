#!/usr/bin/env python3
"""
Verifier for fix_metadata_errors task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_metadata_errors(traj, env_info, task_info):
    """
    Verify that the agent corrected the three metadata errors.
    """
    # 1. Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function unavailable"}

    # 2. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result (Export script may have failed): {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Extract Values
    task_start = result.get("task_start", 0)
    db_mtime = result.get("db_mtime", 0)
    
    einstein_date = result.get("einstein_date", "")
    lecun_doi = result.get("lecun_doi", "")
    turing_pub = result.get("turing_pub", "")

    score = 0
    feedback_parts = []

    # 4. Anti-gaming check: Database modification
    # Zotero updates DB immediately on edit. DB mtime must be > task start.
    if db_mtime <= task_start:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No changes detected in Zotero database (timestamp check failed). Did you perform the edits?"
        }

    # 5. Verify Einstein Date (35 points)
    # Expected: "1905"
    if einstein_date == "1905":
        score += 35
        feedback_parts.append("Einstein date correct (1905)")
    else:
        feedback_parts.append(f"Einstein date incorrect: found '{einstein_date}', expected '1905'")

    # 6. Verify LeCun DOI (35 points)
    # Expected: "10.1038/nature14539" (case insensitive)
    expected_doi = "10.1038/nature14539"
    if lecun_doi.strip().lower() == expected_doi.lower():
        score += 35
        feedback_parts.append("LeCun DOI correct")
    elif lecun_doi == "MISSING":
        feedback_parts.append("LeCun DOI missing (not added)")
    else:
        feedback_parts.append(f"LeCun DOI incorrect: found '{lecun_doi}'")

    # 7. Verify Turing Publication (30 points)
    # Expected: "Mind"
    if turing_pub == "Mind":
        score += 30
        feedback_parts.append("Turing publication correct (Mind)")
    else:
        feedback_parts.append(f"Turing publication incorrect: found '{turing_pub}', expected 'Mind'")

    # 8. Final Calculation
    passed = (score >= 65)  # Need at least 2 out of 3 correct to pass
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }