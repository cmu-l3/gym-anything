#!/usr/bin/env python3
"""
Verifier for register_health_professional task.
Scores out of 100 based on database records, timestamps, and VLM trajectory analysis.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    """Build VLM prompt to verify GNU Health workflow."""
    return """Examine these trajectory screenshots of an agent using the GNU Health Hospital Information System.
    
Did the agent successfully complete the following workflow?
1. Navigate to Health -> Health Professionals.
2. Fill out a form for a new health professional.
3. Enter the name "Maria Santos".
4. Enter the professional license or PUID "MED20247891".
5. Save the record (often a floppy disk icon or confirmation).

Return your analysis in JSON format:
{
    "navigated_to_professionals": true/false,
    "entered_name": true/false,
    "entered_license": true/false,
    "saved_record": true/false,
    "workflow_completed": true/false,
    "observations": "brief explanation of what you see"
}
"""

def verify_register_health_professional(traj, env_info, task_info):
    """
    Verify the health professional registration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/register_health_professional_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Database Checks
    party_found = result.get('party_found', False)
    hp_found = result.get('hp_found', False)
    license_found = result.get('license_found', False)
    task_start = result.get('task_start_time', 0)
    created_epoch = result.get('party_created_epoch', 0)
    initial_hp_count = result.get('initial_hp_count', 0)
    current_hp_count = result.get('current_hp_count', 0)

    # Criterion 1: Party Record (20 pts)
    if party_found:
        score += 20
        feedback_parts.append("Party record for 'Maria Santos' found")
    else:
        feedback_parts.append("MISSING: Party record for 'Maria Santos'")

    # Criterion 2: Health Professional Record (30 pts)
    if hp_found:
        score += 30
        feedback_parts.append("Health Professional record linked to party found")
    else:
        feedback_parts.append("MISSING: Health Professional record")

    # Criterion 3: Professional ID/License (15 pts)
    if license_found:
        score += 15
        feedback_parts.append("Professional ID 'MED20247891' correctly assigned")
    elif hp_found:
        feedback_parts.append("MISSING: Professional ID 'MED20247891' not found in HP record")

    # Criterion 4: Anti-Gaming - Created during task (10 pts)
    created_during_task = (created_epoch >= task_start) if created_epoch > 0 else False
    if party_found and created_during_task:
        score += 10
        feedback_parts.append("Record created during task window")
    elif party_found:
        feedback_parts.append("WARNING: Record timestamp is older than task start")

    # Criterion 5: Anti-Gaming - Count Increased (10 pts)
    hp_count_increased = (current_hp_count > initial_hp_count)
    if hp_count_increased:
        score += 10
        feedback_parts.append(f"HP count increased ({initial_hp_count} -> {current_hp_count})")
    else:
        feedback_parts.append(f"HP count did not increase ({initial_hp_count} -> {current_hp_count})")

    # 3. VLM Verification (15 pts)
    vlm_points = 0
    try:
        # Import dynamically to avoid top-level issues if gym_anything is unavailable
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        all_frames = frames + [final_frame] if final_frame else frames
        
        query_vlm = env_info.get('query_vlm')
        if query_vlm and all_frames:
            vlm_response = query_vlm(images=all_frames, prompt=build_vlm_prompt())
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("workflow_completed"):
                    vlm_points = 15
                    feedback_parts.append("VLM verified successful GUI workflow")
                else:
                    # Partial VLM credit if they did some work
                    if parsed.get("entered_name") or parsed.get("entered_license"):
                        vlm_points = 7
                        feedback_parts.append("VLM verified partial GUI workflow")
                    else:
                        feedback_parts.append("VLM did not detect successful workflow in screenshots")
            else:
                feedback_parts.append("VLM query failed, relying solely on DB state")
        else:
             feedback_parts.append("VLM function or frames unavailable, relying solely on DB state")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # If VLM fails but DB is perfect, grant the points so the agent isn't penalized for infra issues
        if party_found and hp_found and license_found and created_during_task:
            vlm_points = 15
            feedback_parts.append("DB perfect, bypassing VLM failure")
            
    score += vlm_points

    # Success conditions:
    # Must have the Party and HP record at a minimum, and be above 55 total.
    key_criteria_met = party_found and hp_found
    passed = (score >= 55) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "party_found": party_found,
            "hp_found": hp_found,
            "license_found": license_found,
            "created_during_task": created_during_task,
            "count_increased": hp_count_increased,
            "vlm_points": vlm_points
        }
    }