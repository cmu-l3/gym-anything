#!/usr/bin/env python3
"""
Verifier for close_shift task.

Criteria:
1. No open shifts remain in the database (primary success condition).
2. A shift was closed DURING the task window (anti-gaming).
3. VLM Verification: Trajectory shows Back Office navigation.
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory to path for vlm_utils if needed, or assume standard environment
try:
    from vlm_utils import query_vlm, sample_trajectory_frames
except ImportError:
    # Mock for local testing if vlm_utils missing
    def sample_trajectory_frames(traj, n): return []
    def query_vlm(prompt, image=None, images=None): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_close_shift(traj, env_info, task_info):
    """
    Verify the shift was closed.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
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
    
    # 2. Database Verification (Primary)
    open_shifts = result.get('open_shifts_count', 999)
    closed_during_task = result.get('closed_during_task', False)
    app_running = result.get('app_was_running', False)

    # Criterion A: App was running (10 pts)
    if app_running:
        score += 10
        feedback_parts.append("Application was running")

    # Criterion B: No open shifts remain (50 pts)
    if open_shifts == 0:
        score += 50
        feedback_parts.append("No open shifts found in database")
    else:
        feedback_parts.append(f"Found {open_shifts} open shifts (expected 0)")

    # Criterion C: Action happened during task (20 pts)
    if closed_during_task:
        score += 20
        feedback_parts.append("Shift closure timestamp is within task duration")
    elif open_shifts == 0:
        feedback_parts.append("Shift closed, but timestamp verification failed (possible stale state)")

    # 3. VLM Verification (Secondary - 20 pts)
    # Check if agent visited Back Office
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        # Fallback to final screenshot if trajectory empty
        final_path = result.get('screenshot_path')
        # We can't access path directly from host, but traj usually has screenshots
        pass 

    vlm_score = 0
    if frames:
        prompt = """
        Review these screenshots of a Point of Sale (POS) system.
        The user task is to "Close the Shift".
        
        Look for:
        1. Accessing the 'Back Office' or 'Manager' section.
        2. A PIN pad or login screen (usually requiring '1111').
        3. A 'Close Shift', 'End Shift', or 'Shift Management' screen.
        4. A confirmation dialog.
        
        Did the user perform the shift closing workflow?
        Return JSON: {"workflow_detected": true/false, "confidence": "low/medium/high", "reason": "..."}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('workflow_detected', False):
                    vlm_score = 20
                    feedback_parts.append("VLM confirmed shift closure workflow")
                else:
                    feedback_parts.append(f"VLM did not detect workflow: {parsed.get('reason')}")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score

    # Pass logic
    # Must have 0 open shifts AND (closed during task OR VLM confirmation)
    passed = (open_shifts == 0) and (closed_during_task or vlm_score > 0)
    
    if open_shifts == 0 and score < 70:
        # If technical success but low score (e.g. timestamp issue), give partial pass if confident
        if closed_during_task: 
            passed = True
            score = max(score, 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }