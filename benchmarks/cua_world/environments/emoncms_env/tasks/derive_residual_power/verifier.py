#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_derive_residual_power(traj, env_info, task_info):
    """
    Verify the residual power derivation task.
    
    Criteria:
    1. 'residual_power' feed exists (20 pts)
    2. Calculation Logic: Residual value ≈ Main - EV - HeatPump (40 pts)
    3. Integrity Logic: Main Feed value ≈ Main Input (indicating it wasn't modified) (40 pts)
       - If Main Feed ≈ Residual, they subtracted before logging -> 0 pts for integrity.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    feeds = result.get('feeds', [])
    inputs = result.get('inputs', [])
    
    # Helpers
    def get_feed_val(name):
        f = next((f for f in feeds if f['name'] == name), None)
        return float(f['value']) if f else None
        
    def get_input_val(name, nodeid=10):
        i = next((i for i in inputs if int(i.get('nodeid', 0)) == nodeid and i['name'] == name), None)
        return float(i['value']) if i else None

    # Get Metadata
    metadata = task_info.get('metadata', {})
    main_name = metadata.get('main_input_name', 'main_power')
    ev_name = metadata.get('ev_input_name', 'ev_charger')
    hp_name = metadata.get('hp_input_name', 'heat_pump')
    target_feed = metadata.get('target_feed_name', 'residual_power')
    main_feed_name = metadata.get('main_feed_name', 'main_power')
    
    # 1. Check Feed Existence
    res_val = get_feed_val(target_feed)
    if res_val is not None:
        score += 20
        feedback_parts.append(f"Feed '{target_feed}' created.")
    else:
        feedback_parts.append(f"Feed '{target_feed}' NOT found.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # 2. Check Logic Accuracy
    main_in = get_input_val(main_name)
    ev_in = get_input_val(ev_name)
    hp_in = get_input_val(hp_name)
    
    if None in [main_in, ev_in, hp_in]:
        return {"passed": False, "score": score, "feedback": "Critical inputs missing from system."}
        
    expected_residual = main_in - ev_in - hp_in
    tolerance = abs(main_in * 0.1) # 10% tolerance to account for slight timing diffs between input post and feed read
    
    if abs(res_val - expected_residual) < tolerance:
        score += 40
        feedback_parts.append(f"Calculation correct (Expected ~{expected_residual:.1f}, Got {res_val:.1f}).")
    else:
        feedback_parts.append(f"Calculation INCORRECT. Expected ~{expected_residual:.1f} (Main {main_in} - EV {ev_in} - HP {hp_in}), but got {res_val:.1f}.")

    # 3. Integrity Check ("Do No Harm")
    # The 'main_power' feed should still match the 'main_power' input.
    # If the user subtracted BEFORE logging main, the main feed will equal the residual.
    main_feed_val = get_feed_val(main_feed_name)
    
    if main_feed_val is not None:
        # Check if Main Feed was corrupted (equals residual)
        if abs(main_feed_val - res_val) < tolerance and abs(res_val - main_in) > tolerance:
            feedback_parts.append("CRITICAL ERROR: 'main_power' feed equals residual value! You subtracted BEFORE logging the total. The original data log must be preserved.")
        # Check if Main Feed matches Input
        elif abs(main_feed_val - main_in) < tolerance:
            score += 40
            feedback_parts.append("Original 'main_power' log preserved correctly.")
        else:
            feedback_parts.append(f"Main feed value mismatch (Feed: {main_feed_val}, Input: {main_in}).")
    else:
        feedback_parts.append("'main_power' feed deleted or missing.")

    passed = (score == 100)
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }