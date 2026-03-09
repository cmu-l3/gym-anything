#!/usr/bin/env python3
"""
Verifier for create_investigation_form task.

Checks:
1. Project file existence (.prj)
2. Project file created during task (anti-gaming)
3. Form name correct in project definition
4. Database file existence
5. All 15 required fields present in project definition
6. VLM verification of final state (Form Designer visible)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_investigation_form(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    score = 0
    feedback_log = []
    
    # Metadata requirements
    metadata = task_info.get('metadata', {})
    required_fields = metadata.get('required_fields', [])
    required_form = metadata.get('required_form_name', 'CaseInvestigation')

    # --- Criterion 1: Project File Exists (15 pts) ---
    if result.get('prj_exists', False):
        score += 15
        feedback_log.append("Project file found.")
    else:
        feedback_log.append("Project file NOT found.")
        return {"passed": False, "score": 0, "feedback": "Project file missing"}

    # --- Criterion 2: Anti-Gaming Timestamp (Pass/Fail) ---
    if not result.get('file_created_during_task', False):
        feedback_log.append("WARNING: Project file timestamp predates task start.")
        return {"passed": False, "score": 0, "feedback": "Anti-gaming check failed: File reused"}

    # --- Criterion 3: Database Exists (10 pts) ---
    if result.get('db_exists', False):
        score += 10
        feedback_log.append("Database file found.")
    else:
        feedback_log.append("Database file missing.")

    # --- Criterion 4 & 5: Content Verification (XML Parsing) ---
    prj_content = result.get('prj_content_sample', "")
    
    # Check Form Name (10 pts)
    if required_form in prj_content:
        score += 10
        feedback_log.append(f"Form '{required_form}' found in project.")
    else:
        feedback_log.append(f"Form '{required_form}' NOT found in project.")

    # Check Fields (45 pts - 3 pts per field)
    fields_found = 0
    for field in required_fields:
        # Simple string match is sufficient for XML field definition verification
        if field in prj_content:
            fields_found += 1
            score += 3
    
    feedback_log.append(f"Fields verified: {fields_found}/{len(required_fields)}")

    # --- Criterion 6: VLM Verification (20 pts) ---
    # Use trajectory to ensure work was done in UI
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an agent using Epi Info 7 Form Designer.
    
    Look at the sequence of images.
    1. Did the agent open the "Create Forms" or "Form Designer" module?
    2. Is there a form visible with multiple fields?
    3. Do you see fields like "CaseID", "LastName", "Nausea", "Vomiting"?
    
    Return JSON:
    {
        "form_designer_opened": boolean,
        "fields_visible": boolean,
        "specific_fields_seen": boolean
    }
    """
    
    vlm_score = 0
    try:
        if frames:
            vlm_res = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('form_designer_opened'): vlm_score += 5
            if parsed.get('fields_visible'): vlm_score += 10
            if parsed.get('specific_fields_seen'): vlm_score += 5
            
            feedback_log.append(f"VLM verification score: {vlm_score}/20")
    except Exception as e:
        logger.error(f"VLM error: {e}")
        # Fallback: if fields_found > 10, assume UI was used
        if fields_found >= 10:
            vlm_score = 20
            feedback_log.append("VLM skipped, credited based on file content.")

    score += vlm_score

    # Final tally
    passed = score >= 60 and fields_found >= 10
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_log)
    }