#!/usr/bin/env python3
"""
Verifier for expat_immigration_compliance task.

Checks that the agent created exactly 6 immigration records (3 Passports, 3 Visas)
linked to the correct employees, with accurate document numbers and dates.

Uses copy_from_env to read pre-exported JSON database dump to verify correctness.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_expat_immigration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_records = metadata.get('expected_records', {})
    scoring_weights = metadata.get('scoring_weights', {})
    
    pts_per_doc = scoring_weights.get('per_document', 15)
    date_bonus = scoring_weights.get('date_bonus', 10)
    pass_threshold = scoring_weights.get('pass_threshold', 60)

    # 1. Read exported DB state
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    actual_records = result_data.get('records', [])
    
    score = 0
    feedback_parts = []
    
    found_docs = 0
    date_errors = 0

    # 2. Iterate over expected entities
    for empid, docs in expected_records.items():
        for doc_type, expected_doc in docs.items():
            expected_doc_no = expected_doc['doc_no']
            expected_issued = expected_doc['issued']
            expected_expiry = expected_doc['expiry']

            # Find matching document linked to the CORRECT employee
            match = next((r for r in actual_records 
                          if r['documentno'].strip() == expected_doc_no 
                          and r['employeeId'].strip() == empid), None)

            if match:
                score += pts_per_doc
                found_docs += 1
                
                # Verify exact dates
                actual_issued = match.get('issueddate', '')
                actual_expiry = match.get('expirydate', '')
                
                dates_match = (actual_issued == expected_issued) and (actual_expiry == expected_expiry)
                
                if dates_match:
                    feedback_parts.append(f"[{empid}] {doc_type.capitalize()} '{expected_doc_no}' found with correct dates.")
                else:
                    date_errors += 1
                    feedback_parts.append(f"[{empid}] {doc_type.capitalize()} '{expected_doc_no}' found, but date mismatch (got issue:{actual_issued}, expiry:{actual_expiry}).")
            else:
                # Check if it was created but linked to the wrong person
                wrong_link = next((r for r in actual_records if r['documentno'].strip() == expected_doc_no), None)
                if wrong_link:
                    feedback_parts.append(f"[{empid}] {doc_type.capitalize()} '{expected_doc_no}' MISSING (Found linked to wrong employee: {wrong_link['employeeId']}).")
                else:
                    feedback_parts.append(f"[{empid}] {doc_type.capitalize()} '{expected_doc_no}' MISSING entirely.")

    # 3. Apply exact date match bonus if substantive work was done
    # Requirement: At least 4 documents created properly, and zero date errors among all found documents.
    if found_docs >= 4 and date_errors == 0:
        score += date_bonus
        feedback_parts.append(f"Perfect date accuracy bonus awarded (+{date_bonus} pts).")
    elif found_docs > 0 and date_errors > 0:
        feedback_parts.append(f"Date accuracy bonus forfeited due to {date_errors} date error(s).")
    
    # 4. Final calculation
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }