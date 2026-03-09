#!/usr/bin/env python3
"""
Verifier for setup_prod_environment_gate task.
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_prod_environment_gate(traj, env_info, task_info):
    """
    Verify that the 'Production' environment was created with an Approval check.
    
    Scoring:
    - Environment 'Production' exists: 30 pts
    - Approval check added: 30 pts
    - Correct Approver ('TailwindTraders Team'): 25 pts
    - Correct Instructions: 15 pts
    
    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_env_name = metadata.get('expected_env_name', 'Production')
    expected_approver = metadata.get('expected_approver_name', 'TailwindTraders Team')
    expected_instructions = metadata.get('expected_instructions', 'Verify changelog and smoke test results before approving.')

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Windows env, paths might be C:\..., handled by copy_from_env
        copy_from_env("C:\\Users\\Docker\\task_results\\setup_prod_environment_gate_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify Environment Existence (30 pts)
    env_exists = result.get('environment_exists', False)
    env_name = result.get('environment_name', '')
    
    if env_exists and env_name == expected_env_name:
        score += 30
        feedback_parts.append(f"Environment '{expected_env_name}' created")
    elif env_exists:
        # Partial credit for wrong casing? No, strict matching requested.
        feedback_parts.append(f"Environment created but name mismatch ('{env_name}' vs '{expected_env_name}')")
    else:
        feedback_parts.append("Environment 'Production' not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Verify Check Type (30 pts)
    check_type = result.get('check_type')
    if check_type == 'Approval':
        score += 30
        feedback_parts.append("Approval check added")
    else:
        feedback_parts.append(f"Wrong check type found: {check_type}")
    
    # 4. Verify Approver (25 pts)
    approver_name = result.get('approver_name', '')
    if approver_name == expected_approver:
        score += 25
        feedback_parts.append("Correct approver assigned")
    else:
        feedback_parts.append(f"Incorrect approver: '{approver_name}' (expected '{expected_approver}')")
        
    # 5. Verify Instructions (15 pts)
    instructions = result.get('instructions', '')
    if instructions and expected_instructions in instructions:
        score += 15
        feedback_parts.append("Instructions set correctly")
    elif instructions:
        score += 5 # Partial for having some instructions
        feedback_parts.append(f"Instructions mismatch. Got: '{instructions}'")
    else:
        feedback_parts.append("No instructions provided")

    # 6. Secondary VLM Verification (for confidence/sanity check)
    # Only perform if score is high enough to pass, to confirm no UI weirdness
    if score >= 60:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            if final:
                frames.append(final)
            
            # Simple check to ensure they were in the right place
            vlm_prompt = "Does this screenshot show Azure DevOps 'Environments' or 'Approvals' settings?"
            vlm_res = query_vlm(images=[frames[-1]], prompt=vlm_prompt)
            if vlm_res and not vlm_res.get('parsed', {}).get('result', True):
                # We don't penalize heavily if API confirmed, but good for logging
                logger.warning("VLM did not confidently recognize the settings screen.")
        except Exception:
            pass

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }