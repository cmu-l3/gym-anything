#!/usr/bin/env python3
"""
Verifier for create_rdk_motion_task.

Verification Strategy:
1. Programmatic Checks (70 pts):
   - File creation and validity (10 pts)
   - Mandatory Dots component (20 pts)
   - Correct variable usage ($coherence, $direction) (15 pts)
   - Loop configuration with conditions file (15 pts)
   - Routine structure (instructions, fixation, trial) (10 pts)

2. VLM Checks (30 pts):
   - Verify Builder workflow via trajectory frames.
   - Confirm visual presence of Dots component settings or flow.

Pass threshold: 60 points AND mandatory Dots component.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_rdk_motion_task(traj, env_info, task_info):
    """Verify the RDK motion task implementation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback_parts = []
    
    # 1. File Validity (10 pts)
    if result.get('file_exists') and result.get('is_valid_xml'):
        if result.get('file_modified'):
            score += 10
            feedback_parts.append("Valid experiment file created")
        else:
            score += 5
            feedback_parts.append("Experiment file exists but not modified")
    else:
        feedback_parts.append("FAIL: Experiment file missing or invalid")

    # 2. Dots Component - MANDATORY (20 pts)
    has_dots = result.get('has_dots_component', False)
    if has_dots:
        score += 20
        feedback_parts.append("Dots component found")
    else:
        feedback_parts.append("FAIL: No Dots component found (mandatory)")

    # 3. Variable Usage (15 pts)
    vars_ok = 0
    if result.get('coherence_variable_used'):
        vars_ok += 1
    if result.get('direction_variable_used'):
        vars_ok += 1
    
    if vars_ok == 2:
        score += 15
        feedback_parts.append("Variables correctly configured")
    elif vars_ok == 1:
        score += 7
        feedback_parts.append("Partial variable configuration")
    else:
        feedback_parts.append("Variables for coherence/direction not set correctly")

    # 4. Loop & Conditions (15 pts)
    if result.get('has_loop'):
        cond_file = result.get('loop_conditions_file', '')
        if 'motion_conditions.csv' in cond_file:
            score += 15
            feedback_parts.append("Loop linked to correct conditions file")
        elif cond_file:
            score += 10
            feedback_parts.append("Loop exists but wrong condition file")
        else:
            score += 5
            feedback_parts.append("Loop exists but no conditions file")
    else:
        feedback_parts.append("No loop found")

    # 5. Routine Structure (10 pts)
    routines_found = 0
    if result.get('has_instructions'): routines_found += 1
    if result.get('has_fixation'): routines_found += 1
    if result.get('has_trial_routine'): routines_found += 1
    
    if routines_found == 3:
        score += 10
        feedback_parts.append("All routines (instruct, fix, trial) found")
    elif routines_found > 0:
        score += 5
        feedback_parts.append(f"Some routines found ({routines_found}/3)")

    # 6. VLM Verification (30 pts)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        prompt = """
        Review these screenshots of a user working in PsychoPy Builder.
        Look for:
        1. An experiment flow with multiple routines (e.g., instructions, trial).
        2. A "Dots" or "RDK" component being configured (look for dot properties like field shape, coherence).
        3. A Loop being added around routines.
        
        Does the user appear to be building a Random Dot Motion experiment?
        Respond JSON: {"appears_valid": bool, "confidence": "high/med/low", "evidence": "list of items seen"}
        """
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('appears_valid'):
                vlm_score = 30
                feedback_parts.append("VLM confirms RDK construction workflow")
            else:
                feedback_parts.append("VLM could not confirm workflow")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if programmatic score is high, assume VLM would pass
        if score >= 60:
            vlm_score = 20
            feedback_parts.append("VLM skipped, fallback credit awarded")

    score += vlm_score

    # Final Pass Logic
    # Must have dots component and respectable score
    passed = (score >= 60) and has_dots

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }