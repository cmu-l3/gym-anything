#!/usr/bin/env python3
"""
Verifier for batch_gender_correction task.

Checks database state to ensure:
1. Target female patients (misclassified as H) are now F (50 pts)
2. Distractor patients (Compound names like Jean-Marie) are still H (20 pts)
3. Ambiguous patients (Claude) not in list are still H (20 pts)
4. Baseline male patients are still H (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_gender_correction(traj, env_info, task_info):
    """
    Verify that the batch update was performed correctly and safely.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expectations
    # Targets: Should become 'F'
    TARGETS = ['GUID_T1', 'GUID_T2', 'GUID_T3', 'GUID_T4']
    
    # Distractors: Should remain 'H' (Jean-Marie, Jean-Pierre, Claude)
    DISTRACTORS = ['GUID_D1', 'GUID_D2', 'GUID_D3']
    
    # Baseline: Should remain 'H' (Pierre)
    BASELINE = ['GUID_B1']

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Database query failed: {result['error']}"}

    records = result.get('records', {})
    
    # Criterion 1: Targets Corrected (50 points)
    correct_targets = 0
    for guid in TARGETS:
        sex = records.get(guid, 'MISSING')
        if sex == 'F':
            correct_targets += 1
        else:
            feedback_parts.append(f"Target {guid} is '{sex}' (Expected 'F')")
            
    target_score = (correct_targets / len(TARGETS)) * 50
    score += target_score
    if correct_targets == len(TARGETS):
        feedback_parts.append("All misclassified females corrected")

    # Criterion 2: Distractors Protected (20 points)
    # Crucial check: Did they accidentally update "Jean-Marie" because "Marie" is in the list?
    protected_distractors = 0
    for guid in DISTRACTORS:
        sex = records.get(guid, 'MISSING')
        if sex == 'H':
            protected_distractors += 1
        else:
            feedback_parts.append(f"Distractor {guid} changed to '{sex}' (Should be 'H')")
            
    distractor_score = (protected_distractors / len(DISTRACTORS)) * 20
    score += distractor_score
    if protected_distractors == len(DISTRACTORS):
        feedback_parts.append("Compound/Ambiguous names correctly preserved")

    # Criterion 3: Baseline Integrity (10 points)
    baseline_ok = 0
    for guid in BASELINE:
        sex = records.get(guid, 'MISSING')
        if sex == 'H':
            baseline_ok += 1
    
    baseline_score = (baseline_ok / len(BASELINE)) * 10
    score += baseline_score

    # Criterion 4: Anti-Gaming / Mass Update Check (20 points)
    # If they just updated EVERYONE to 'F', they fail this.
    # We check if the distractors were preserved (covered in Crit 2) 
    # but we can also check the total count if we had a larger DB.
    # For this specific task, preserving distractors is the best anti-gaming check.
    # We'll allocate remaining 20 points to "No False Positives" specifically for Jean-Marie type errors.
    
    # Specifically check GUID_D1 (Jean-Marie)
    jean_marie_safe = records.get('GUID_D1') == 'H'
    if jean_marie_safe:
        score += 20
        feedback_parts.append("Strict matching verified (Jean-Marie preserved)")
    else:
        feedback_parts.append("Strict matching FAILED (Jean-Marie incorrectly updated)")

    # Final logic
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": records
    }