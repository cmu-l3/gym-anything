#!/usr/bin/env python3
"""
Verifier for manual_attendance_entry task.

Verifies:
1. Database Record: Checks if attendance record for EMP003 on 2025-01-15 exists with correct times.
2. VLM Trajectory: Verifies the agent navigated the UI and entered data manually.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

# Assuming gym_anything structure (vlm import mocked for file gen)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for mock environments
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manual_attendance_entry(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Mapping from Windows path in guest to temp file in host
        # The export script writes to C:\Users\Docker\AppData\Local\Temp\task_result.json
        # We need to know the path copy_from_env expects. Usually it handles the OS specific path separators if provided correctly.
        # Assuming standard location defined in export script.
        guest_path = "C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json"
        copy_from_env(guest_path, temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Database Verification (Primary)
    db_record_exists = result.get('db_record_exists', False)
    in_time = result.get('retrieved_in_time', "")
    out_time = result.get('retrieved_out_time', "")

    if db_record_exists:
        score += 30
        feedback.append("Attendance record created.")
        
        # Check In Time (Allow 9:00 or 09:00 or 9:0)
        if in_time in ["09:00", "9:00", "9:0"]:
            score += 20
            feedback.append("Correct In-Time (09:00).")
        else:
            feedback.append(f"Incorrect In-Time: {in_time} (Expected 09:00).")

        # Check Out Time (Allow 18:00 or 18:0)
        if out_time in ["18:00", "18:0"]:
            score += 20
            feedback.append("Correct Out-Time (18:00).")
        else:
            feedback.append(f"Incorrect Out-Time: {out_time} (Expected 18:00).")
    else:
        feedback.append("No attendance record found in database.")

    # 3. VLM Verification (Trajectory)
    # We want to see the Attendance Screen and Manual Entry form
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if frames:
        prompt = """
        Analyze these screenshots of a user interacting with AttendHRM.
        The user goal is to manually enter attendance for "Robert Johnson".
        
        Look for:
        1. Navigation to "Attendance" module.
        2. A form showing employee selection ("Robert Johnson" or "EMP003").
        3. Date selection ("15/01/2025" or similar).
        4. Time entry fields (09:00, 18:00).
        5. A save action or success message.
        
        Return JSON:
        {
            "attendance_screen_visible": true/false,
            "employee_selected": true/false,
            "times_entered": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_res = query_vlm(images=frames + [final_frame] if final_frame else frames, prompt=prompt)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('attendance_screen_visible'):
                score += 10
            if parsed.get('employee_selected'):
                score += 10
            if parsed.get('times_entered'):
                score += 10
            
            feedback.append(f"VLM Analysis: {json.dumps(parsed)}")

    # 4. Pass Logic
    # Must have DB record + correct times (at least one) + some VLM evidence or perfect DB match
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }