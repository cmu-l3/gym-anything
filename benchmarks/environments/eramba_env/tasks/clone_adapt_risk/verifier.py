#!/usr/bin/env python3
"""
Verifier for clone_adapt_risk@1

Verifies that the agent:
1. Created a new risk "Phishing Attacks on Remote Contractors"
2. Adapted the description to "Remote Contractors"
3. Set the mitigation strategy to "Transfer" (ID 4)
4. Preserved the original risk
5. Actually performed the work during the task window
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clone_adapt_risk(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Get Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_title = metadata.get('target_risk_title', 'Phishing Attacks on Remote Contractors')
    required_str = metadata.get('required_string', 'Remote Contractors')
    required_strategy = metadata.get('required_strategy_id', 4)

    new_risk = result.get('new_risk', {})
    
    # Criterion 1: New Risk Exists (30 pts)
    if result.get('new_risk_found') and new_risk.get('title') == target_title:
        score += 30
        feedback.append("Success: New risk record created with correct title.")
        
        # Anti-gaming check: Created timestamp
        created_ts = new_risk.get('created_ts', 0)
        task_start = result.get('task_start', 0)
        if created_ts > task_start:
             feedback.append("Verified: Record created during task session.")
        else:
             score -= 30
             feedback.append("Failure: Record creation timestamp predates task start (Anti-gaming).")
    else:
        feedback.append(f"Failure: Risk '{target_title}' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Mitigation Strategy (30 pts)
    # Strategy 4 = Transfer
    actual_strategy = new_risk.get('strategy_id')
    if actual_strategy == required_strategy:
        score += 30
        feedback.append("Success: Mitigation strategy set to 'Transfer'.")
    else:
        feedback.append(f"Partial: Mitigation strategy ID is {actual_strategy}, expected {required_strategy} (Transfer).")

    # Criterion 3: Description Adapted (20 pts)
    description = new_risk.get('description', '')
    if required_str.lower() in description.lower():
        score += 20
        feedback.append(f"Success: Description contains '{required_str}'.")
    else:
        feedback.append(f"Partial: Description does not contain required text '{required_str}'.")

    # Criterion 4: Cloning/Data Completeness (10 pts)
    # Checked by comparing threats field to source
    if result.get('cloning_verified'):
        score += 10
        feedback.append("Success: Risk details (threats) match source, indicating successful clone/copy.")
    else:
        feedback.append("Info: Risk details do not match source (fresh creation assumed).")

    # Criterion 5: Original Risk Preserved (10 pts)
    if result.get('original_risk_preserved'):
        score += 10
        feedback.append("Success: Original risk remains intact.")
    else:
        score -= 20 # Penalty for destroying source data
        feedback.append("Failure: Original risk was modified or deleted.")

    # 4. Final Verdict
    # Pass threshold: 70 points (Must have created risk + correct strategy + mostly correct description)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }