#!/usr/bin/env python3
"""
Verifier for relocate_class_section task.

Task: Move 'Introduction to Biology' Period 2 from Room 304 to Science Lab.
      Do NOT move Period 3.

Verification Strategy:
1. Load result JSON from container.
2. Check if Period 2 section's room_id matches Science Lab ID.
3. Check if Period 3 section's room_id matches Room 304 ID (Anti-gaming/Precision).
4. VLM Trajectory Check: Verify UI interaction (Scheduling/Courses menu).
"""

import json
import tempfile
import os
import logging
import sys
from pathlib import Path

# Add parent directory for shared utilities if needed, 
# but we will define VLM helpers inline or assume framework provides them.
# Standard pattern:
sys.path.insert(0, str(Path(__file__).parent.parent))
try:
    from vlm_utils import query_vlm, sample_trajectory_frames
except ImportError:
    # Fallback/Mock if running standalone
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying an agent's actions in OpenSIS (Student Information System).
The goal was to change a course's room assignment.

Review these screenshots of the agent's workflow.
1. Did the agent navigate to 'Scheduling' and then 'Courses'?
2. Did the agent select a course (Introduction to Biology)?
3. Did the agent open a screen allowing them to edit a 'Course Section' or 'Period'?
4. Is there any visibility of a Room dropdown menu or Room selection?

Respond in JSON format:
{
    "scheduling_menu_accessed": true/false,
    "course_selected": true/false,
    "section_edit_screen_visible": true/false,
    "room_selection_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_relocate_class_section(traj, env_info, task_info):
    """
    Verify the relocation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
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

    # 2. Extract Data
    initial_ids = result.get("initial_ids", {})
    current_state = result.get("current_state", {})
    
    target_section_id = initial_ids.get("target_section_id")
    distractor_section_id = initial_ids.get("distractor_section_id")
    science_lab_id = initial_ids.get("science_lab_id")
    room_304_id = initial_ids.get("room_304_id")
    
    current_target_room = current_state.get("target_section_room_id")
    current_distractor_room = current_state.get("distractor_section_room_id")

    # IDs come as integers in JSON usually, but strings in bash. Ensure types match.
    # Convert all to strings for comparison
    science_lab_id = str(science_lab_id)
    room_304_id = str(room_304_id)
    current_target_room = str(current_target_room)
    current_distractor_room = str(current_distractor_room)

    score = 0
    feedback_parts = []
    
    # 3. Primary Verification: Target Section Moved (50 pts)
    if current_target_room == science_lab_id:
        score += 50
        feedback_parts.append("Success: Period 2 section moved to Science Lab.")
    elif current_target_room == room_304_id:
        feedback_parts.append("Fail: Period 2 section is still in Room 304.")
    else:
        feedback_parts.append(f"Fail: Period 2 section is in unknown room ID {current_target_room}.")

    # 4. Secondary Verification: Distractor Section Unchanged (30 pts)
    # This ensures they didn't just bulk update all sections or the wrong one.
    if current_distractor_room == room_304_id:
        score += 30
        feedback_parts.append("Success: Period 3 section correctly remained in Room 304.")
    elif current_distractor_room == science_lab_id:
        score -= 10 # Penalty for moving the wrong one
        feedback_parts.append("Fail: Period 3 section was incorrectly moved to Science Lab.")
    else:
        feedback_parts.append("Fail: Period 3 section was moved to an unknown room.")

    # 5. VLM Verification (20 pts)
    # Use trajectory frames to prove UI interaction
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
        parsed = vlm_res.get("parsed", {}) if vlm_res else {}
        
        vlm_score = 0
        if parsed.get("scheduling_menu_accessed"): vlm_score += 5
        if parsed.get("course_selected"): vlm_score += 5
        if parsed.get("section_edit_screen_visible"): vlm_score += 5
        if parsed.get("room_selection_visible"): vlm_score += 5
        
        score += vlm_score
        feedback_parts.append(f"VLM verification score: {vlm_score}/20")
    else:
        feedback_parts.append("Warning: No trajectory frames available for VLM check.")

    # 6. Final Decision
    passed = (current_target_room == science_lab_id) and (current_distractor_room == room_304_id)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }