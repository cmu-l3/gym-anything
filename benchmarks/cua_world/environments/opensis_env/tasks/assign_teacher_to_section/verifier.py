#!/usr/bin/env python3
"""
Verifier for assign_teacher_to_section task.

Critera:
1. Teacher Assigned (Database): Check if teacher_id is no longer NULL for the target section.
2. Correct Teacher: Verify the assigned teacher is "Patricia Hernandez".
3. Anti-Gaming: Verify state changed from NULL -> ID during the task.
4. VLM Verification: Use trajectory frames to confirm navigation (Scheduling > Courses).
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import shared VLM utils if available, otherwise define mock/local
try:
    from vlm_utils import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for standalone testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(prompt, images): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_teacher(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_first = metadata.get('target_teacher_first', 'Patricia')
    target_last = metadata.get('target_teacher_last', 'Hernandez')

    # 2. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate Criteria
    score = 0
    feedback = []
    
    # Criterion A: App was running (10 pts)
    if result.get("app_running", False):
        score += 10
    else:
        feedback.append("Browser closed prematurely.")

    # Criterion B: Teacher Assigned (State Changed from NULL) (30 pts)
    state_changed = result.get("state_changed", False)
    teacher_assigned = result.get("teacher_assigned", False)
    
    if teacher_assigned:
        if state_changed:
            score += 30
            feedback.append("A teacher was successfully assigned to the section.")
        else:
            # This implies teacher was already set, or something weird happened with setup
            feedback.append("Teacher field is set, but state did not change from initial (possible setup error or no action).")
    else:
        feedback.append("No teacher is assigned to the course section.")

    # Criterion C: Correct Teacher (40 pts)
    final_first = result.get("teacher_first_name", "")
    final_last = result.get("teacher_last_name", "")
    
    name_match = (final_first.lower() == target_first.lower() and 
                  final_last.lower() == target_last.lower())

    if teacher_assigned:
        if name_match:
            score += 40
            feedback.append(f"Correct teacher assigned: {target_first} {target_last}.")
        else:
            feedback.append(f"Incorrect teacher assigned. Expected {target_first} {target_last}, found {final_first} {final_last}.")

    # Criterion D: VLM Trajectory Verification (20 pts)
    # Check if agent visited Scheduling -> Courses
    vlm_score = 0
    trajectory_images = sample_trajectory_frames(traj, n=4)
    if trajectory_images:
        prompt = """
        Analyze these screenshots of the OpenSIS Student Information System.
        Did the user navigate to the 'Scheduling' module and the 'Courses' section?
        Look for:
        1. A menu with 'Scheduling' selected or expanded.
        2. A list of courses (e.g., 'Chemistry 101').
        3. A form or dropdown where a teacher is being selected.
        
        Answer with JSON: {"scheduling_visited": bool, "teacher_selection_visible": bool}
        """
        
        vlm_resp = query_vlm(images=trajectory_images, prompt=prompt)
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("scheduling_visited"):
                vlm_score += 10
            if parsed.get("teacher_selection_visible"):
                vlm_score += 10
            
            if vlm_score > 0:
                feedback.append(f"Visual verification passed ({vlm_score}/20 pts).")
    
    score += vlm_score

    # 4. Final Verdict
    # Pass if score >= 70 AND correct teacher is assigned
    passed = (score >= 70) and name_match

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }