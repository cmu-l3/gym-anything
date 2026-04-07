#!/usr/bin/env python3
"""
Verifier for configure_exam_accessibility_features task.

Verifies that specific booleans mapped to accessibility features within 
the SEB Server UI have successfully been enabled and saved against the right config.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_accessibility_features(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Load exported state safely
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    config_exists = result.get('config_exists', False)
    if not config_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Exam configuration 'ENGL 204: Modernist Literature Final' not found."
        }
    else:
        feedback_parts.append("Config found")

    def is_enabled(val):
        """Checks boolean string/integer representations pulled from db"""
        return val in ['true', '1']

    # Retrieve status values
    spell_check = is_enabled(result.get('spell_check', 'false'))
    text_search = is_enabled(result.get('text_search', 'false'))
    zooming = is_enabled(result.get('zooming', 'false'))
    
    # Score the checkboxes
    if spell_check:
        score += 30
        feedback_parts.append("Spell Check enabled")
    else:
        feedback_parts.append("Spell Check missing")

    if text_search:
        score += 30
        feedback_parts.append("Text Search enabled")
    else:
        feedback_parts.append("Text Search missing")
        
    if zooming:
        score += 30
        feedback_parts.append("Zooming enabled")
    else:
        feedback_parts.append("Zooming missing")
        
    # Evaluate Anti-Gaming (Confirm changes were legitimately saved to the config during task window)
    task_start = result.get('task_start_time', 0.0)
    changed_ts = result.get('changed_timestamp', 0.0)
    
    # 2 second padding gracefully covers rapid inserts at setup phase vs active modification
    if changed_ts >= (task_start - 2):
        score += 10
        feedback_parts.append("Config was modified and saved")
    else:
        feedback_parts.append("Config was not modified during the task session (Timestamps identical to baseline)")

    # Strict grading criteria matches our 100 max specification
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }