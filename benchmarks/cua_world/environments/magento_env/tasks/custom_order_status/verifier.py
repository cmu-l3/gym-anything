#!/usr/bin/env python3
"""Verifier for Custom Order Status task in Magento.

Task: Create 3 custom order statuses with specific labels, state assignments, and visibility settings.

Scoring:
- 3 statuses * 25 pts each (Status existence + Mapping + Visibility)
- 25 pts for anti-gaming (creation of new records)
- Pass threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_custom_order_status(traj, env_info, task_info):
    """
    Verify creation and configuration of custom order statuses.
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load expected data from metadata
    metadata = task_info.get('metadata', {})
    expected_statuses = metadata.get('statuses', [])
    
    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/order_status_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result: {result}")
    
    score = 0
    feedback_parts = []
    
    # 1. Anti-gaming check (25 pts max)
    # Did the user actually create new records?
    init_stat = result.get('initial_status_count', 0)
    curr_stat = result.get('current_status_count', 0)
    init_state = result.get('initial_state_count', 0)
    curr_state = result.get('current_state_count', 0)
    
    status_delta = max(0, curr_stat - init_stat)
    state_delta = max(0, curr_state - init_state)
    
    # We expect 3 new statuses and 3 new state mappings
    if status_delta >= 3:
        score += 10
        feedback_parts.append("Created 3+ new statuses (10 pts)")
    elif status_delta > 0:
        score += 3 * status_delta
        feedback_parts.append(f"Created {status_delta} new statuses (partial)")
        
    if state_delta >= 3:
        score += 15
        feedback_parts.append("Created 3+ new state mappings (15 pts)")
    elif state_delta > 0:
        score += 5 * state_delta
        feedback_parts.append(f"Created {state_delta} new mappings (partial)")

    # 2. Check each specific status (75 pts total: 25 pts per status)
    result_statuses = result.get('statuses', {})
    
    for exp in expected_statuses:
        code = exp['code']
        exp_label = exp['label']
        exp_state = exp['state']
        exp_vis = str(exp['visible'])
        
        actual = result_statuses.get(code, {})
        
        status_score = 0
        status_feedback = []
        
        # A. Status exists and label matches (10 pts)
        if actual.get('exists'):
            act_label = actual.get('label', '')
            if act_label.strip() == exp_label:
                status_score += 10
                status_feedback.append("Label OK")
            else:
                status_score += 5
                status_feedback.append(f"Label mismatch ('{act_label}' vs '{exp_label}')")
        else:
            status_feedback.append("Status not created")
            feedback_parts.append(f"[{code}]: {', '.join(status_feedback)}")
            continue # specific code not found, skip rest of checks for this one
            
        # B. State assignment matches (10 pts)
        act_state = actual.get('assigned_state', '').strip()
        if act_state == exp_state:
            status_score += 10
            status_feedback.append("State OK")
        elif not act_state:
            status_feedback.append("Not assigned to state")
        else:
            status_feedback.append(f"Wrong state ('{act_state}' vs '{exp_state}')")
            
        # C. Visibility matches (5 pts)
        act_vis = str(actual.get('visible_on_front', '')).strip()
        if act_vis == exp_vis:
            status_score += 5
            status_feedback.append("Visibility OK")
        else:
            status_feedback.append(f"Wrong visibility")
            
        score += status_score
        feedback_parts.append(f"[{code}]: {', '.join(status_feedback)} ({status_score}/25)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }