#!/usr/bin/env python3
"""Verifier for apply_team_patch task."""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_apply_team_patch(traj, env_info, task_info):
    """
    Verify that the patch was applied correctly to the RadiationTherapy project.

    Criteria:
    1. DoseCalculator.java content contains the fix (Inverse Square Law) (30 pts)
    2. CalibrationConstants.java content contains the update (1.035) (30 pts)
    3. Files were modified during the task (Anti-gaming) (10 pts)
    4. Project compiles (10 pts)
    5. VLM: Verification of 'Apply Patch' usage and/or passing tests (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_isf = metadata.get('expected_isf_logic', 'Math.pow(distanceSourceToTumor / 100.0, 2)')
    expected_const = metadata.get('expected_const_value', '1.035')

    # Load result from export script
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task result file"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify DoseCalculator Content (30 pts)
    calc_content = result.get('calc_content', '')
    if expected_isf in calc_content:
        score += 30
        feedback_parts.append("DoseCalculator fix applied (ISF logic present)")
    else:
        feedback_parts.append("DoseCalculator fix NOT found")

    # 2. Verify CalibrationConstants Content (30 pts)
    const_content = result.get('const_content', '')
    if expected_const in const_content:
        score += 30
        feedback_parts.append("CalibrationConstants updated (1.035 found)")
    else:
        feedback_parts.append(f"CalibrationConstants update NOT found (expected {expected_const})")

    # 3. Anti-Gaming: Check modification (10 pts)
    if result.get('calc_modified') or result.get('const_modified'):
        score += 10
        feedback_parts.append("Files modified during task")
    else:
        feedback_parts.append("Files NOT modified during task")

    # 4. Compilation Check (10 pts)
    if result.get('compiled'):
        score += 10
        feedback_parts.append("Project compilation valid")
    else:
        feedback_parts.append("No compiled class files found (did tests run?)")

    # 5. VLM Verification (20 pts)
    vlm_score = 0
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, num_samples=5)
            final_ss = get_final_screenshot(traj)
            if final_ss:
                frames.append(final_ss)
                
            prompt = """
            You are verifying an Eclipse IDE task where the agent applies a patch and runs tests.
            Review the screenshots and answer:
            1. Do you see the "Team > Apply Patch" wizard or dialog?
            2. Do you see the JUnit view/tab?
            3. Do you see a GREEN bar in the JUnit view (indicating tests passed)?
            
            Return JSON:
            {
                "apply_patch_seen": boolean,
                "junit_green_bar_seen": boolean,
                "summary": "string"
            }
            """
            
            vlm_resp = query_vlm(prompt=prompt, images=frames)
            if vlm_resp and vlm_resp.get('success'):
                parsed = vlm_resp.get('parsed', {})
                if parsed.get('apply_patch_seen'):
                    vlm_score += 10
                    feedback_parts.append("VLM: Apply Patch wizard usage detected")
                if parsed.get('junit_green_bar_seen'):
                    vlm_score += 10
                    feedback_parts.append("VLM: JUnit green bar detected")
                
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            
    score += vlm_score

    # Final Pass/Fail Logic
    # Must have both code fixes present (60 pts) + files modified (10 pts) = 70 pts minimum
    key_criteria_met = (expected_isf in calc_content) and (expected_const in const_content) and (result.get('calc_modified') or result.get('const_modified'))
    
    return {
        "passed": score >= 70 and key_criteria_met,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }