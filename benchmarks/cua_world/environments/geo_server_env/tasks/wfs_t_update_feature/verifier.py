#!/usr/bin/env python3
"""
Verifier for wfs_t_update_feature task.

Criteria:
1. Database state: Shanghai pop_max must be 28543210 (40 pts)
2. Database scope: Only 1 record should have this value (20 pts)
3. Process evidence: Request XML exists and contains valid tags (20 pts)
4. Process evidence: Response XML indicates success (20 pts)
"""

import json
import tempfile
import os
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wfs_t_update(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_val = metadata.get('target_value', 28543210)

    # Load result
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

    score = 0
    feedback_parts = []
    
    current_pop = result.get('current_population', 0)
    match_count = result.get('match_count', 0)
    
    # Criterion 1: Target Updated (40 pts)
    # Check if Shanghai has the correct population
    if int(current_pop) == int(target_val):
        score += 40
        feedback_parts.append("Target (Shanghai) updated correctly.")
    else:
        feedback_parts.append(f"Target update failed. Expected {target_val}, got {current_pop}.")

    # Criterion 2: Scope Correct (20 pts)
    # Ensure we didn't update the whole table or wrong records.
    # We expect exactly 1 match for this specific population value (since it's a specific number).
    # If the user updated ALL cities to this value, match_count would be high.
    if match_count == 1:
        score += 20
        feedback_parts.append("Update scope correct (single record).")
    elif match_count > 1:
        feedback_parts.append(f"Update scope too broad! {match_count} records have the target value.")
    elif match_count == 0:
        # Already handled by Criterion 1 failure usually, but explicit here
        pass

    # Criterion 3: Request Artifact (20 pts)
    if result.get('request_file_exists'):
        # Decode content to check for key WFS-T tags
        try:
            content = base64.b64decode(result.get('request_content_b64', '')).decode('utf-8', errors='ignore')
            if 'wfs:Transaction' in content or 'Transaction' in content:
                if 'wfs:Update' in content or 'Update' in content:
                    score += 20
                    feedback_parts.append("Valid WFS-T Update XML found.")
                else:
                    score += 10
                    feedback_parts.append("WFS Transaction found but missing Update tag.")
            else:
                score += 5
                feedback_parts.append("Request file exists but content unclear.")
        except Exception:
            score += 5
            feedback_parts.append("Request file exists.")
    else:
        feedback_parts.append("Request XML file missing.")

    # Criterion 4: Response Artifact (20 pts)
    if result.get('response_file_exists'):
        if result.get('response_indicates_success'):
            score += 20
            feedback_parts.append("Response indicates successful transaction.")
        else:
            score += 10
            feedback_parts.append("Response file exists but success not confirmed.")
    else:
        feedback_parts.append("Response XML file missing.")

    # Pass Threshold
    passed = (score >= 60) and (int(current_pop) == int(target_val))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }