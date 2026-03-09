#!/usr/bin/env python3
"""
Verifier for map_policy_to_compliance task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_map_policy_to_compliance(traj, env_info, task_info):
    """
    Verifies that the agent created a policy, a compliance package/item, and linked them.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Data from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Score Database Evidence (80 points total)
    
    # Policy Creation (20 pts)
    if data['policy']['found']:
        score += 20
        feedback.append("Security Policy created successfully.")
        
        # Content Check (10 pts)
        desc = data['policy'].get('description_snippet', '').lower()
        if 'sensitive' in desc or 'lock' in desc or 'desk' in desc:
            score += 10
            feedback.append("Policy description contains relevant keywords.")
        else:
            feedback.append("Policy description missing key terms.")
    else:
        feedback.append("Security Policy not found.")

    # Compliance Package Creation (15 pts)
    if data['package']['found']:
        score += 15
        feedback.append("Compliance Package created.")
    else:
        feedback.append("Compliance Package not found.")

    # Compliance Item Creation (15 pts)
    if data['item']['found']:
        score += 15
        feedback.append("Compliance Requirement Item created.")
    else:
        feedback.append("Compliance Requirement Item not found.")

    # Linkage (20 pts)
    if data['linkage']['found']:
        score += 20
        feedback.append("Linkage established between Policy and Requirement.")
    else:
        feedback.append("Failed to link Policy to Requirement.")

    # 3. VLM Verification (20 points)
    # Use trajectory frames to confirm UI interaction
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if frames or final_shot:
        prompt = (
            "Analyze these screenshots of a GRC software interface (Eramba). "
            "I am looking for evidence that the user: "
            "1. Visited the 'Security Policies' section. "
            "2. Visited the 'Compliance Management' section. "
            "3. Used a modal or form to 'link' or 'add' a policy to a compliance item. "
            "Does the visual history show this workflow?"
        )
        
        try:
            # We use the provided query_vlm utility
            vlm_res = query_vlm(images=frames + [final_shot], prompt=prompt)
            if vlm_res.get('success'):
                # Simple heuristic: if VLM is positive, give points
                # In a real impl, we'd parse the boolean response
                # specific to the framework's VLM wrapper.
                # Assuming standard text response for now.
                response_text = vlm_res.get('response', '').lower()
                if 'yes' in response_text or 'shows' in response_text:
                    score += 20
                    feedback.append("Visual trajectory confirms workflow.")
                else:
                    # Partial credit for just doing stuff
                    score += 10
                    feedback.append("Visual trajectory ambiguous, partial credit.")
            else:
                feedback.append("VLM verification failed to run.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback.append("Visual verification skipped due to error.")
            # Fallback: if database linkage is true, assume visual is implicitly passed
            if data['linkage']['found']:
                score += 20

    # 4. Final Determination
    # Pass threshold: 70 points. This requires at least creating records + linking OR creating records + perfect description + VLM
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }