#!/usr/bin/env python3
"""
Verifier for create_project_template task in ManageEngine ServiceDesk Plus.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_project_template(traj, env_info, task_info):
    """
    Verifies that the agent created a Project Template with the correct hierarchy.
    
    Scoring:
    - Template Created: 40 pts
    - Milestone Added: 30 pts
    - Task Added under Milestone: 30 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results from container
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
    
    # 2. Score Database Verification
    template_found = result.get("template_found", False)
    milestone_found = result.get("milestone_found", False)
    task_found = result.get("task_found", False)

    if template_found:
        score += 40
        feedback_parts.append("Project Template 'New Branch Office Setup' created successfully.")
    else:
        feedback_parts.append("Project Template NOT found in database.")

    if milestone_found:
        score += 30
        feedback_parts.append("Milestone 'Infrastructure Preparation' correctly added to template.")
    else:
        feedback_parts.append("Milestone missing or not linked to template.")

    if task_found:
        score += 30
        feedback_parts.append("Task 'Site Survey and Cabling Check' correctly added to milestone.")
    else:
        feedback_parts.append("Task missing or not linked to milestone.")

    # 3. VLM Verification (Trajectory Check)
    # Only if database check failed or for extra confirmation
    # We use VLM to ensure the agent actually interacted with the UI if DB query logic missed something
    # (e.g., if SDP schema versions differ wildly)
    
    # However, DB verification is primary. If score is low, we check VLM to give partial credit 
    # if it LOOKS like they did it but DB query failed.
    
    if score < 100:
        logger.info("Score < 100, running VLM verification...")
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        prompt = """
        You are verifying a software agent using ManageEngine ServiceDesk Plus.
        The goal is to Create a Project Template.
        
        Look for these steps in the screenshots:
        1. User navigating to 'Projects' or 'Project Templates'.
        2. User filling out a form with Name 'New Branch Office Setup'.
        3. User adding a Milestone 'Infrastructure Preparation'.
        4. User adding a Task 'Site Survey'.
        
        Did the agent appear to complete the creation of the project template with these details?
        """
        
        try:
            vlm_response = query_vlm(images=frames + [final_frame], prompt=prompt)
            if vlm_response.get("success", False) and "yes" in vlm_response.get("response", "").lower():
                # If VLM is confident but DB failed, we might note it, but we stick to DB for hard points usually.
                # Here we won't override DB score to avoid false positives, but add feedback.
                feedback_parts.append("(VLM observed correct workflow steps, possible DB sync issue).")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # 4. Final Verdict
    # Pass threshold: 70 points (Must have Template + Milestone at least)
    passed = (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }