#!/usr/bin/env python3
"""
Verifier for batch_nir_correction task.
Checks database updates and log file creation.
"""

import json
import os
import tempfile
import re

def normalize_ssn(ssn):
    """Remove spaces and non-digit chars for comparison."""
    if not ssn:
        return ""
    return re.sub(r'\D', '', str(ssn))

def verify_batch_nir_correction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', {})
    distractor_db = metadata.get('distractor_db', {})
    distractor_csv_names = metadata.get('distractor_csv', [])

    # Get result from container
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
    feedback = []
    
    db_state = result.get('db_state', {})
    log_info = result.get('log_file', {})

    # Criterion 1: Correct Updates (50 points)
    # Check if target patients match expected NIR
    correct_count = 0
    total_targets = len(targets)
    
    for key, expected_ssn in targets.items():
        actual_ssn_raw = db_state.get(key, "")
        actual_ssn = normalize_ssn(actual_ssn_raw)
        
        # We accept either exact match or match of normalized form
        if actual_ssn == normalize_ssn(expected_ssn):
            correct_count += 1
        else:
            feedback.append(f"Failed update for {key}: expected {expected_ssn}, got '{actual_ssn_raw}'")

    if total_targets > 0:
        update_score = int((correct_count / total_targets) * 50)
        score += update_score
        feedback.append(f"Update Score: {update_score}/50 ({correct_count}/{total_targets} correct)")
    else:
        feedback.append("Configuration error: No targets defined")

    # Criterion 2: Distractor Preservation (20 points)
    # Check if existing patient NOT in CSV was touched
    distractor_passed = True
    for key, original_ssn in distractor_db.items():
        actual_ssn_raw = db_state.get(key, "")
        actual_ssn = normalize_ssn(actual_ssn_raw)
        expected_norm = normalize_ssn(original_ssn)
        
        if actual_ssn != expected_norm:
            distractor_passed = False
            feedback.append(f"Distractor modified! {key} changed from {original_ssn} to {actual_ssn_raw}")
    
    if distractor_passed:
        score += 20
        feedback.append("Distractor records preserved (20/20)")
    else:
        feedback.append("Distractor records were incorrectly modified (0/20)")

    # Criterion 3: Log File (30 points)
    # 10 pts for existence + creation during task
    # 20 pts for correct content (contains missing patient name)
    log_exists = log_info.get('exists', False)
    log_created = log_info.get('created_during_task', False)
    log_content = log_info.get('content', "")

    if log_exists and log_created:
        score += 10
        feedback.append("Log file created (10/10)")
        
        content_correct = True
        for name in distractor_csv_names:
            if name not in log_content:
                content_correct = False
                feedback.append(f"Log file missing entry for: {name}")
        
        # Check against false positives (target names shouldn't be in log)
        for key in targets.keys():
            last_name = key.split('_')[0]
            if last_name in log_content:
                content_correct = False
                feedback.append(f"Log file incorrectly contains found patient: {last_name}")

        if content_correct:
            score += 20
            feedback.append("Log content correct (20/20)")
        else:
            feedback.append("Log content incorrect (0/20)")
    else:
        feedback.append("Log file not created or not new (0/30)")

    # Final tally
    passed = (score >= 70) and (correct_count >= total_targets / 2)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }