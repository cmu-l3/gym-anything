#!/usr/bin/env python3
"""
Verifier for Check-In Appointment task in OpenEMR

Verifies that the agent successfully checked in a patient by changing
the appointment status to 'Arrived' (@).

Verification Strategy:
1. Primary: Database state check via exported JSON
2. Secondary: Trajectory-based VLM verification (confirms calendar interaction)
3. Anti-gaming: Timestamp verification ensures status changed during task

Scoring (100 points total):
- Appointment status is '@' (Arrived): 50 points
- Correct patient (pid=3): 20 points
- Status actually changed (not pre-set): 15 points
- VLM confirms calendar interaction: 15 points
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Valid "arrived" statuses in OpenEMR
VALID_ARRIVED_STATUSES = ['@', '~', '<']  # Arrived, Arrived Late, In Exam Room


def verify_check_in_appointment(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the patient appointment was checked in correctly.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available for verification"
        }
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_status = metadata.get('expected_status', '@')
    
    score = 0
    feedback_parts = []
    subscores = {
        "status_arrived": False,
        "correct_patient": False,
        "status_changed": False,
        "vlm_verified": False
    }
    
    # Copy result JSON from container
    result = None
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/check_in_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read verification data: {str(e)}"
        }
    
    if not result:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No verification data available"
        }
    
    logger.info(f"Verification data: {json.dumps(result, indent=2)}")
    
    # Extract data from result
    appointment_found = result.get('appointment_found', False)
    appointment = result.get('appointment', {})
    initial_status = result.get('initial_status', '')
    status_is_arrived = result.get('status_is_arrived', False)
    status_changed = result.get('status_changed', False)
    modified_during_task = result.get('modified_during_task', False)
    task_start = result.get('task_start_time', 0)
    
    # Check if appointment was found
    if not appointment_found:
        feedback_parts.append("FAIL: No appointment found for patient today")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    # CRITERION 1: Correct patient (20 points)
    appt_pid = appointment.get('pid', '')
    try:
        appt_pid_int = int(appt_pid) if appt_pid else 0
    except ValueError:
        appt_pid_int = 0
        
    if appt_pid_int == expected_pid:
        score += 20
        subscores["correct_patient"] = True
        feedback_parts.append(f"✓ Correct patient (pid={expected_pid})")
    else:
        feedback_parts.append(f"✗ Wrong patient - expected pid={expected_pid}, got {appt_pid}")
        # Critical failure - wrong patient
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    # CRITERION 2: Appointment status is Arrived (50 points)
    current_status = appointment.get('status', '')
    
    if current_status in VALID_ARRIVED_STATUSES:
        score += 50
        subscores["status_arrived"] = True
        status_name = {
            '@': 'Arrived',
            '~': 'Arrived Late',
            '<': 'In Exam Room'
        }.get(current_status, current_status)
        feedback_parts.append(f"✓ Status is '{status_name}' ({current_status})")
    else:
        status_display = current_status if current_status else '(blank/scheduled)'
        feedback_parts.append(f"✗ Status is '{status_display}' - expected '@' (Arrived)")
    
    # CRITERION 3: Status actually changed during task (15 points)
    # This prevents gaming by pre-setting the status
    if status_changed and modified_during_task:
        score += 15
        subscores["status_changed"] = True
        feedback_parts.append(f"✓ Status changed from '{initial_status}' during task")
    elif status_changed:
        # Status changed but timestamp unclear - partial credit
        score += 8
        feedback_parts.append(f"~ Status changed from '{initial_status}' (timestamp unverified)")
    elif current_status in VALID_ARRIVED_STATUSES and initial_status in VALID_ARRIVED_STATUSES:
        # Status was already arrived - possible gaming
        feedback_parts.append(f"⚠ Status was already '{initial_status}' before task started")
    else:
        feedback_parts.append(f"✗ Status did not change from initial state")
    
    # CRITERION 4: VLM trajectory verification (15 points)
    # Check if agent actually interacted with the calendar
    vlm_score = verify_via_trajectory(traj, env_info)
    if vlm_score > 0:
        score += vlm_score
        subscores["vlm_verified"] = True
        feedback_parts.append(f"✓ Calendar interaction verified via screenshots (+{vlm_score})")
    else:
        feedback_parts.append("~ Could not verify calendar interaction via screenshots")
    
    # Ensure score is within bounds
    score = max(0, min(100, score))
    
    # Determine pass/fail
    # Must have correct patient AND arrived status to pass
    passed = subscores["correct_patient"] and subscores["status_arrived"] and score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "appointment": appointment,
            "initial_status": initial_status,
            "expected_status": expected_status
        }
    }


def verify_via_trajectory(traj: Dict[str, Any], env_info: Dict[str, Any]) -> int:
    """
    Verify task completion using trajectory screenshots and VLM.
    
    Checks if agent navigated to calendar and interacted with appointment.
    
    Args:
        traj: Trajectory with frames
        env_info: Environment info with query_vlm function
        
    Returns:
        Score (0-15) based on VLM verification
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        logger.warning("VLM query function not available")
        return 0
    
    # Try to get trajectory frames
    frames = traj.get('frames', [])
    if not frames:
        logger.warning("No trajectory frames available")
        return 0
    
    # Sample frames from trajectory (beginning, middle, end)
    sample_indices = []
    n_frames = len(frames)
    if n_frames >= 3:
        sample_indices = [0, n_frames // 2, n_frames - 1]
    elif n_frames >= 1:
        sample_indices = [n_frames - 1]
    
    sampled_frames = [frames[i] for i in sample_indices if i < len(frames)]
    
    if not sampled_frames:
        logger.warning("Could not sample frames from trajectory")
        return 0
    
    # Create VLM prompt to verify calendar interaction
    vlm_prompt = """You are verifying if a computer agent successfully checked in a patient appointment in OpenEMR.

TASK: Check in patient "Jayson Fadel" for their scheduled appointment by changing the status to "Arrived".

Look at these screenshots from the agent's work session and determine:
1. Did the agent navigate to a calendar/scheduler view in OpenEMR?
2. Can you see any appointment or calendar interface?
3. Is there evidence of clicking on an appointment or changing its status?
4. Does any screenshot show an appointment details dialog or status change?

Respond in JSON format:
{
    "saw_calendar_view": true/false,
    "saw_appointment_interface": true/false,
    "saw_status_change_action": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you observed in the screenshots"
}
"""
    
    try:
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=sampled_frames
        )
        
        if not vlm_result.get("success"):
            logger.warning(f"VLM query failed: {vlm_result.get('error')}")
            return 0
        
        parsed = vlm_result.get("parsed", {})
        
        saw_calendar = parsed.get("saw_calendar_view", False)
        saw_appointment = parsed.get("saw_appointment_interface", False)
        saw_status_change = parsed.get("saw_status_change_action", False)
        confidence = parsed.get("confidence", "low")
        
        # Score based on what was observed
        vlm_score = 0
        if saw_calendar:
            vlm_score += 5
        if saw_appointment:
            vlm_score += 5
        if saw_status_change:
            vlm_score += 5
        
        # Adjust for confidence
        if confidence == "low" and vlm_score > 0:
            vlm_score = max(vlm_score - 3, 0)
        
        logger.info(f"VLM verification: calendar={saw_calendar}, appointment={saw_appointment}, "
                   f"status_change={saw_status_change}, confidence={confidence}, score={vlm_score}")
        
        return min(vlm_score, 15)
        
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return 0


if __name__ == "__main__":
    # For testing outside of gym-anything
    import subprocess
    
    def mock_copy(src, dst):
        subprocess.run(["cp", src, dst], check=True)
    
    mock_env_info = {
        'copy_from_env': mock_copy
    }
    
    mock_task_info = {
        'metadata': {
            'patient_pid': 3,
            'expected_status': '@'
        }
    }
    
    mock_traj = {'frames': []}
    
    result = verify_check_in_appointment(mock_traj, mock_env_info, mock_task_info)
    print(f"Score: {result['score']}")
    print(f"Passed: {result['passed']}")
    print(f"Feedback: {result['feedback']}")