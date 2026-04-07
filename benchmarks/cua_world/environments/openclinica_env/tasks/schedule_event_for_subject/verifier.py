#!/usr/bin/env python3
"""Verifier for schedule_event_for_subject task."""

import json
import tempfile
import os
import logging
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames
from vlm_utils import query_vlm as _query_vlm_direct

logger = logging.getLogger(__name__)


def _build_vlm_prompt():
    """Build VLM prompt to verify trajectory of scheduling an event."""
    return """You are verifying if an AI agent successfully scheduled a clinical trial visit in OpenClinica.
I am providing you with multiple sequential screenshots (a trajectory) from the agent's session, ending with the final state.

Look at these frames and determine:
1. Is OpenClinica visible?
2. Did the agent navigate to the subject matrix or a subject's record page?
3. Did the agent open an "event schedule" form or calendar date picker?
4. Do the frames show a progression of filling out a scheduling form (entering a date/location) and saving it?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "navigated_to_subject": true/false,
    "opened_schedule_form": true/false,
    "workflow_progression_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def verify_schedule_event(traj, env_info, task_info):
    """
    Verify schedule_event_for_subject task completion.

    Scoring (100 points total):
    - Event exists for SS_101 (Screening Visit): 30 pts
    - Date is correct (2025-01-15 +/- 1 day for tz): 20 pts
    - Location is correct: 15 pts
    - Event status is 'scheduled' (1): 10 pts
    - Control subjects untouched: 10 pts
    - Anti-gaming timestamp (event created after task start): 10 pts
    - VLM Trajectory (workflow progression): 5 pts

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/schedule_event_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
    except Exception:
        expected_nonce = ""
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    result_nonce = result.get('result_nonce', '')
    if expected_nonce and result_nonce != expected_nonce:
        return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: Result file nonce mismatch."}

    score = 0
    feedback_parts = []

    # Criterion 1: Event Exists (30 pts)
    event_found = result.get('event_found', False)
    if event_found:
        score += 30
        feedback_parts.append("Event 'Screening Visit' found for SS_101 (+30)")
    else:
        feedback_parts.append("FAIL: Event 'Screening Visit' NOT found for SS_101 (0/30)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)} # Early exit if core task failed

    # Criterion 2: Date is Correct (20 pts)
    # Target date: 2025-01-15. Accepting 14, 15, or 16 due to potential timezone differences in DB timestamps
    event_date = result.get('event_date', '')
    if any(date in event_date for date in ["2025-01-14", "2025-01-15", "2025-01-16"]):
        score += 20
        feedback_parts.append(f"Date correct: {event_date} (+20)")
    else:
        feedback_parts.append(f"Date incorrect: {event_date} (expected 2025-01-15) (0/20)")

    # Criterion 3: Location is Correct (15 pts)
    event_location = result.get('event_location', '').lower()
    if 'boston general' in event_location or 'clinical research unit' in event_location:
        score += 15
        feedback_parts.append("Location correct (+15)")
    else:
        feedback_parts.append(f"Location incorrect: '{event_location}' (0/15)")

    # Criterion 4: Status is 'scheduled' (status_id = 1) (10 pts)
    event_status_id = result.get('event_status_id', 0)
    if event_status_id == 1:
        score += 10
        feedback_parts.append("Status is 'scheduled' (+10)")
    else:
        feedback_parts.append(f"Status is not scheduled (id={event_status_id}) (0/10)")

    # Criterion 5: Control subjects untouched (10 pts)
    ss102_count = result.get('ss102_event_count', 0)
    ss103_count = result.get('ss103_event_count', 0)
    if ss102_count == 0 and ss103_count == 0:
        score += 10
        feedback_parts.append("Control subjects untouched (+10)")
    else:
        feedback_parts.append("FAIL: Other subjects incorrectly modified (0/10)")

    # Criterion 6: Anti-gaming timestamp (10 pts)
    task_start = result.get('task_start_time', 0)
    event_created = result.get('event_created_time', 0)
    if event_created >= task_start and task_start > 0:
        score += 10
        feedback_parts.append("Timestamp check passed (+10)")
    else:
        feedback_parts.append("FAIL: Event was not created during this task session (0/10)")

    # Criterion 7: VLM Trajectory (5 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        # Get 4 trajectory frames + the final frame to prove workflow progression
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_result = query_vlm(prompt=_build_vlm_prompt(), images=frames)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            workflow_ok = parsed.get("workflow_progression_visible", False)
            if workflow_ok:
                score += 5
                feedback_parts.append("VLM visual trajectory check passed (+5)")
            else:
                feedback_parts.append("VLM could not confirm scheduling workflow progression")
        else:
            feedback_parts.append("VLM query failed or returned no result")

    passed = score >= 60 and event_found
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }