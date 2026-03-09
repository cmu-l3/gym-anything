#!/usr/bin/env python3
"""
Verifier for configure_predictive_dialer task.
Checks if Vicidial campaign settings match the required configuration.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_predictive_dialer(traj, env_info, task_info):
    """
    Verify campaign settings in Vicidial database.
    
    Expected configuration:
    - Dial Method: RATIO
    - Auto Dial Level: 1.5
    - Hopper Level: 500
    - Dial Timeout: 26
    - Campaign Recording: ALLCALLS
    - Drop Call Seconds: 5
    - Campaign Caller ID: 2125551000
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_values', {
        "dial_method": "RATIO",
        "auto_dial_level": "1.5",
        "hopper_level": "500",
        "dial_timeout": "26",
        "campaign_rec": "ALLCALLS",
        "drop_call_seconds": "5",
        "campaign_cid": "2125551000"
    })
    
    scoring = metadata.get('scoring', {})
    
    # Load initial state (to detect do-nothing)
    initial_state = {}
    temp_initial = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/initial_state.json", temp_initial.name)
        with open(temp_initial.name, 'r') as f:
            initial_state = json.load(f)
    except Exception:
        logger.warning("Could not load initial state, skipping anti-gaming diff check")
    finally:
        if os.path.exists(temp_initial.name):
            os.unlink(temp_initial.name)

    # Load result
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Basic Checks
    if not result.get('campaign_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Campaign SALESOUT was deleted or does not exist."
        }

    current = result.get('current_state', {})
    score = 0
    feedback_parts = []
    
    # 3. Verify Fields
    # Field: Dial Method
    key = "dial_method"
    if current.get(key) == expected[key]:
        pts = scoring.get(key, 10)
        score += pts
        feedback_parts.append(f"✓ Dial Method ({pts} pts)")
    elif current.get(key) == initial_state.get(key):
         feedback_parts.append(f"✗ Dial Method unchanged")
    else:
         feedback_parts.append(f"✗ Dial Method incorrect: found {current.get(key)}")

    # Field: Auto Dial Level
    # Note: DB might store 1.50 or 1.5, handle strictness if needed but usually string match works if standard input
    key = "auto_dial_level"
    # Normalize expected/actual to float for comparison if possible, else string
    try:
        val_float = float(current.get(key, 0))
        exp_float = float(expected[key])
        if abs(val_float - exp_float) < 0.01:
            pts = scoring.get(key, 10)
            score += pts
            feedback_parts.append(f"✓ Auto Dial Level ({pts} pts)")
        elif current.get(key) == initial_state.get(key):
            feedback_parts.append(f"✗ Auto Dial Level unchanged")
        else:
            feedback_parts.append(f"✗ Auto Dial Level incorrect: {current.get(key)}")
    except ValueError:
        feedback_parts.append(f"✗ Auto Dial Level invalid format")

    # Field: Hopper Level
    key = "hopper_level"
    if str(current.get(key)) == str(expected[key]):
        pts = scoring.get(key, 10)
        score += pts
        feedback_parts.append(f"✓ Hopper Level ({pts} pts)")
    else:
        feedback_parts.append(f"✗ Hopper Level incorrect: {current.get(key)}")

    # Field: Dial Timeout
    key = "dial_timeout"
    if str(current.get(key)) == str(expected[key]):
        pts = scoring.get(key, 10)
        score += pts
        feedback_parts.append(f"✓ Dial Timeout ({pts} pts)")
    else:
        feedback_parts.append(f"✗ Dial Timeout incorrect: {current.get(key)}")

    # Field: Campaign Recording
    key = "campaign_rec"
    if current.get(key) == expected[key]:
        pts = scoring.get(key, 10)
        score += pts
        feedback_parts.append(f"✓ Campaign Recording ({pts} pts)")
    else:
        feedback_parts.append(f"✗ Campaign Recording incorrect: {current.get(key)}")

    # Field: Drop Call Seconds
    key = "drop_call_seconds"
    if str(current.get(key)) == str(expected[key]):
        pts = scoring.get(key, 10)
        score += pts
        feedback_parts.append(f"✓ Drop Call Seconds ({pts} pts)")
    else:
        feedback_parts.append(f"✗ Drop Call Seconds incorrect: {current.get(key)}")

    # Field: Campaign Caller ID
    key = "campaign_cid"
    if str(current.get(key)) == str(expected[key]):
        pts = scoring.get(key, 10)
        score += pts
        feedback_parts.append(f"✓ Caller ID ({pts} pts)")
    else:
        feedback_parts.append(f"✗ Caller ID incorrect: {current.get(key)}")

    # 4. Final Scoring
    # Pass threshold: 60/100
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }