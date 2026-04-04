#!/usr/bin/env python3
"""
Verifier for configure_custom_mime_types task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_custom_mime_types(traj, env_info, task_info):
    """
    Verify that custom MIME types were configured correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Load result from container
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

    # 1. Primary Verification: Live HTTP Headers (40 pts each)
    # The agent must have reloaded Apache for this to work
    gcode_passed = result.get('gcode_check_passed', False)
    lua_passed = result.get('lua_check_passed', False)
    
    if gcode_passed:
        score += 40
        feedback_parts.append(".gcode MIME type correct")
    else:
        actual = result.get('gcode_header_actual', 'None')
        feedback_parts.append(f".gcode failed (Got: {actual})")

    if lua_passed:
        score += 40
        feedback_parts.append(".lua MIME type correct")
    else:
        actual = result.get('lua_header_actual', 'None')
        feedback_parts.append(f".lua failed (Got: {actual})")

    # 2. Secondary Verification: Config File (20 pts)
    # Checks if directives exist in file, even if reload failed
    config_has_directives = result.get('config_has_directives', False)
    config_modified = result.get('config_modified_during_task', False)
    
    if config_has_directives:
        score += 15
        feedback_parts.append("Apache config contains directives")
    
    if config_modified:
        score += 5
        feedback_parts.append("Config modified during task")
    else:
        # Anti-gaming check: if live checks passed but file wasn't modified, 
        # it might be a pre-existing state (though setup cleans it).
        if gcode_passed or lua_passed:
            feedback_parts.append("Warning: Config file timestamp not updated (reload only?)")

    # 3. Tertiary Verification: VLM Trajectory (Penalty only)
    # If score is high but no visual evidence of work, deduct points?
    # Actually, let's use it to confirm UI usage if programmatic checks are ambiguous.
    # In this task, programmatic checks are very strong. We will just log VLM result.
    
    # Calculate final status
    passed = score >= 80  # Must get both live checks OR one live + config
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }