#!/usr/bin/env python3
"""
Verifier for reschedule_course_section@1 task.

Criteria:
1. Anti-gaming: State MUST have changed from initial (5 pts)
2. Room Verification: Room must be '205' (35 pts)
3. Period Verification: Period must be '3' (35 pts)
4. Navigation/Process: VLM Verification of edit screen (25 pts)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities if available in the environment context
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Mock for testing if not available
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(prompt, images=None, image=None): return {"success": False}

def verify_reschedule_course_section(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the course section was rescheduled correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_room = metadata.get('target_room', '205')
    target_period_short = metadata.get('target_period_short', '3')
    
    # 1. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Check Database Results
    section_found = result.get('section_found', False)
    current_room = str(result.get('current_room', '')).strip()
    current_period_short = str(result.get('current_period_short', '')).strip()
    state_changed = result.get('state_changed', False)

    if not section_found:
        return {"passed": False, "score": 0, "feedback": "CRITICAL: Course section for ENG101 not found in database."}

    # Criterion 1: Anti-Gaming (5 pts)
    # Did the agent actually do something?
    if state_changed:
        score += 5
        feedback.append("State changed from initial (Anti-gaming check passed).")
    else:
        feedback.append("No changes detected in database.")

    # Criterion 2: Room Check (35 pts)
    if current_room == target_room:
        score += 35
        feedback.append(f"Room correctly updated to {target_room}.")
    else:
        feedback.append(f"Room is '{current_room}', expected '{target_room}'.")

    # Criterion 3: Period Check (35 pts)
    if current_period_short == target_period_short:
        score += 35
        feedback.append(f"Period correctly updated to Period {target_period_short}.")
    else:
        feedback.append(f"Period is '{current_period_short}', expected '{target_period_short}'.")

    # Criterion 4: VLM Process Verification (25 pts)
    # Check if we saw the scheduling interface
    frames = sample_trajectory_frames(traj, n=5)
    vlm_score = 0
    if frames:
        prompt = """
        Review these screenshots of a user interacting with OpenSIS Student Information System.
        The user goal is to reschedule a course section.
        
        Look for:
        1. The 'Scheduling' module or 'Courses' list.
        2. A form with 'Room' and 'Period' dropdowns or inputs.
        3. The course 'Introduction to Literature' or 'ENG101'.
        
        Return JSON: {"evidence_found": boolean, "confidence": float}
        """
        
        vlm_res = query_vlm(prompt=prompt, images=frames)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('evidence_found'):
                vlm_score = 25
                feedback.append("VLM verified scheduling workflow.")
            else:
                feedback.append("VLM did not observe clear scheduling workflow.")
        else:
            # Fallback if VLM fails but DB is correct
            if score >= 70:
                vlm_score = 25
                feedback.append("VLM unavailable, trusting DB results.")
    else:
        # No frames, fallback
        if score >= 70:
            vlm_score = 25
    
    score += vlm_score

    passed = (score >= 60) and (current_room == target_room or current_period_short == target_period_short)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "room_correct": current_room == target_room,
            "period_correct": current_period_short == target_period_short,
            "state_changed": state_changed
        }
    }