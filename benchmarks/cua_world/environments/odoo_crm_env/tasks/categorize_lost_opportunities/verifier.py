#!/usr/bin/env python3
"""
Verifier for categorize_lost_opportunities task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_categorize_lost_opportunities(traj, env_info, task_info):
    """
    Verify that the three opportunities have been assigned the correct Lost Reasons.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected mappings from task metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', {
        "Enterprise License - Summit Financial": "Price too high",
        "Fleet Tracking System - BlueWave Logistics": "Lacking Features",
        "Cloud Storage Migration - Apex Healthcare": "Budget Freeze"
    })

    # Load result from container
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

    opp_data = result.get('opportunity_data', {})
    if "error" in opp_data:
        return {"passed": False, "score": 0, "feedback": f"Error querying Odoo: {opp_data['error']}"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Check each target
    correct_count = 0
    active_penalty = False

    for opp_name, expected_reason in targets.items():
        data = opp_data.get(opp_name)
        
        if not data:
            feedback_parts.append(f"❌ '{opp_name}' not found")
            continue

        # Check Active State (Should remain False/Lost)
        is_active = data.get('active', True)
        if is_active:
            feedback_parts.append(f"⚠️ '{opp_name}' was restored to Active (should be Lost)")
            active_penalty = True
        
        # Check Reason
        actual_reason = data.get('lost_reason_name')
        if actual_reason == expected_reason:
            score += 30
            correct_count += 1
            feedback_parts.append(f"✅ '{opp_name}': Correctly set to '{actual_reason}'")
        else:
            feedback_parts.append(f"❌ '{opp_name}': Expected '{expected_reason}', got '{actual_reason}'")

    # Bonus for keeping them lost (10 pts)
    if not active_penalty and correct_count > 0:
        score += 10
        feedback_parts.append("✅ All records correctly maintained in Lost state")
    elif active_penalty:
        feedback_parts.append("⚠️ Penalty: Some records were left Active (not Lost)")

    # Pass threshold
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }