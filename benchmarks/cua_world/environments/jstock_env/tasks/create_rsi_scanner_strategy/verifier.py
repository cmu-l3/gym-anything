#!/usr/bin/env python3
"""
Verifier for create_rsi_scanner_strategy task.

Criteria:
1. JStock config files must be modified AFTER task start (Anti-gaming).
2. "Oversold RSI" string must be found in modified config.
3. "RSI" or "Relative Strength Index" must be found in modified config.
4. "30" (threshold) must be found in modified config.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_rsi_scanner_strategy(traj, env_info, task_info):
    """
    Verifies that the agent created and saved the RSI scanner strategy.
    """
    # 1. Setup copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Extract signals
    file_modified = result.get("file_modified", False)
    found_name = result.get("found_name", False)
    found_indicator = result.get("found_indicator", False)
    found_value = result.get("found_value", False)
    app_running = result.get("app_running", False)

    # 4. Scoring Logic
    score = 0
    feedback_parts = []

    # Criterion A: Configuration Persistence (10 pts)
    if file_modified:
        score += 10
        feedback_parts.append("Configuration saved (files modified).")
    else:
        feedback_parts.append("No configuration saved.")

    # Criterion B: Correct Strategy Name (30 pts)
    if found_name:
        score += 30
        feedback_parts.append("Strategy name 'Oversold RSI' found.")
    else:
        feedback_parts.append("Strategy name 'Oversold RSI' NOT found.")

    # Criterion C: Correct Indicator (30 pts)
    if found_indicator:
        score += 30
        feedback_parts.append("Indicator 'RSI' found.")
    else:
        feedback_parts.append("Indicator 'RSI' NOT found.")

    # Criterion D: Correct Threshold (30 pts)
    if found_value:
        score += 30
        feedback_parts.append("Threshold value '30' found.")
    else:
        feedback_parts.append("Threshold value '30' NOT found.")

    # Penalty for crashing app (optional, usually tasks just fail, but good for feedback)
    if not app_running:
        feedback_parts.append("(Warning: JStock was closed/crashed).")

    # 5. Final Determination
    # Pass if Score >= 90 (Needs Name, Indicator, and Value roughly correct)
    # We require 100 for perfect, but 90 allows for some minor glitch in file mod time check 
    # if the grep found the strings anyway (though grep relies on mod time in export.sh).
    # Since export.sh ONLY greps modified files, if `file_modified` is false, score is 0.
    
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }