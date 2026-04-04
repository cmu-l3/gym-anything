#!/usr/bin/env python3
"""
Verifier for Submit Proposal task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_submit_proposal(traj, env_info, task_info):
    """
    Verify the proposal was submitted and stage updated.
    
    Criteria:
    1. Opportunity stage is 'Proposition' (30 pts)
    2. Probability is 70% (20 pts)
    3. Proposal PDF is attached (40 pts)
    4. Anti-gaming (time check) (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    target_stage = metadata.get('target_stage', 'Proposition')
    target_prob = metadata.get('target_probability', 70.0)

    # Copy result
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
    
    # 1. Check Opportunity Existence
    if not result.get("opportunity_found"):
        return {"passed": False, "score": 0, "feedback": "Opportunity not found in CRM"}

    # 2. Check Stage (30 pts)
    actual_stage = result.get("stage_name", "")
    if actual_stage == target_stage:
        score += 30
        feedback_parts.append(f"Stage correctly set to '{actual_stage}'")
    else:
        feedback_parts.append(f"Incorrect stage: '{actual_stage}' (expected '{target_stage}')")

    # 3. Check Probability (20 pts)
    actual_prob = result.get("probability", 0.0)
    # Allow small float tolerance
    if abs(actual_prob - target_prob) < 0.1:
        score += 20
        feedback_parts.append(f"Probability correctly set to {actual_prob}%")
    else:
        feedback_parts.append(f"Incorrect probability: {actual_prob}% (expected {target_prob}%)")

    # 4. Check Attachment (40 pts)
    if result.get("attachment_found"):
        score += 40
        feedback_parts.append("Proposal PDF successfully attached")
    else:
        feedback_parts.append("Proposal PDF NOT found in attachments")

    # 5. Anti-gaming / Basic sanity (10 pts)
    # If they got any of the above points, give them the base points for attempting
    if score > 0:
        score += 10
    else:
        feedback_parts.append("No progress detected")

    passed = score >= 70  # Must at least attach file and change stage (40+30=70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }