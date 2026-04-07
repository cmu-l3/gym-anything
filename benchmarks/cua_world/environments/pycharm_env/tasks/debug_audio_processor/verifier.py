#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_debug_audio_processor(traj, env_info, task_info):
    """
    Verify debug_audio_processor task.
    
    Criteria:
    1. Bug 1 (Duration) Fixed: 30 pts
    2. Bug 2 (Filter) Fixed: 35 pts
    3. Bug 3 (RMS) Fixed: 35 pts
    
    Checks both the independent verification script results (primary)
    and the pytest exit code (secondary confirmation).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    feedback = []
    
    verify_data = result.get('verify_script', {})
    
    # Check Bug 1: Duration
    if verify_data.get('bug1_duration_fixed', False):
        score += 30
        feedback.append("Bug 1 (Stereo Duration) fixed.")
    else:
        feedback.append("Bug 1 (Stereo Duration) NOT fixed.")
        
    # Check Bug 2: Filter
    if verify_data.get('bug2_filter_fixed', False):
        score += 35
        feedback.append("Bug 2 (Filter Cutoff) fixed.")
    else:
        feedback.append("Bug 2 (Filter Cutoff) NOT fixed or still crashing.")
        
    # Check Bug 3: RMS
    if verify_data.get('bug3_rms_fixed', False):
        score += 35
        feedback.append("Bug 3 (RMS Calculation) fixed.")
    else:
        feedback.append("Bug 3 (RMS Calculation) NOT fixed.")
        
    # Check overall test suite status (sanity check)
    pytest_code = result.get('pytest_exit_code', 1)
    if pytest_code == 0:
        feedback.append("All unit tests passed.")
    else:
        feedback.append(f"Unit tests failed (exit code {pytest_code}).")
        # Optional: Penalty if script says fixed but tests fail?
        # Usually implies broken tests, but we trust the verification script more.
        
    return {
        "passed": score >= 100,
        "score": score,
        "feedback": " | ".join(feedback)
    }