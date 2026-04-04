#!/usr/bin/env python3
"""
Verifier for Generate Billing Report task.
Checks if the generated report contains the correct target invoices and excludes distractors.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_billing_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/billing_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Data
    file_exists = result.get('file_exists', False)
    is_new = result.get('is_new_file', False)
    text = result.get('extracted_text', "").lower() # Normalize to lowercase
    ground_truth = result.get('ground_truth', {})
    
    targets = ground_truth.get('targets', [])
    distractors = ground_truth.get('distractors', [])

    score = 0
    feedback = []

    # Criterion 1: File Existence & Freshness (20 pts)
    if file_exists:
        if is_new:
            score += 20
            feedback.append("Report file created successfully.")
        else:
            score += 5
            feedback.append("Report file exists but timestamp suggests it wasn't created during this task.")
    else:
        feedback.append("No report file found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Target Inclusion (40 pts)
    # Check if target Invoice IDs or Dates + Code appear in text
    targets_found = 0
    for t in targets:
        # Search for Invoice ID
        if str(t['id']) in text:
            targets_found += 1
        # Fallback: If text doesn't contain IDs (e.g. summarized report), check for code count?
        # Ideally, a report lists rows. If extracted text is messy, ID is best unique key.
    
    if len(targets) > 0:
        target_score = (targets_found / len(targets)) * 40
        score += target_score
        feedback.append(f"Found {targets_found}/{len(targets)} target billing records.")
    
    # Criterion 3: Distractor Exclusion (30 pts)
    # Verify NO distractor IDs are present
    distractors_found = 0
    for d in distractors:
        if str(d['id']) in text:
            distractors_found += 1
    
    if distractors_found == 0:
        score += 30
        feedback.append("Correctly excluded all distractor records.")
    else:
        # Penalize
        feedback.append(f"Incorrectly included {distractors_found} distractor records.")

    # Criterion 4: Service Code & Provider Check (10 pts)
    # Basic keyword check
    if "k013" in text:
        score += 5
        feedback.append("Target service code 'K013' found in text.")
    
    if "chen" in text or "sarah" in text:
        score += 5
        feedback.append("Provider name found in text.")
        
    if "a007" in text:
        score -= 10
        feedback.append("Penalty: Found distractor code 'A007' in text.")

    # Final Score cap
    score = max(0, min(100, score))
    
    # Pass logic: Need >80 and at least some targets found
    passed = (score >= 80) and (targets_found > 0)

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }