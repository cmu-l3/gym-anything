#!/usr/bin/env python3
"""
Verifier for record_sell_transaction@1.

Verifies that the agent correctly recorded a sell transaction in JStock.
Criteria:
1. sellportfolio.csv exists and was modified during the task.
2. The CSV contains an entry for AAPL.
3. The entry details match: 40 units, $225.75, "Mar 15, 2024".
4. The buy portfolio was not corrupted.
5. VLM check verifies UI interaction (trajectory).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_sell_transaction(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_units = metadata.get('expected_units', 40.0)
    expected_price = metadata.get('expected_price', 225.75)
    expected_date = metadata.get('expected_date_str', "Mar 15, 2024")
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 3. Verify File Attributes
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "sellportfolio.csv was not created"}
    
    if result.get('file_modified_during_task'):
        score += 10
        feedback_parts.append("File modified during task")
    else:
        feedback_parts.append("File NOT modified during task (anti-gaming fail)")
        
    if result.get('buy_integrity'):
        score += 5
        feedback_parts.append("Buy portfolio preserved")
    else:
        feedback_parts.append("Buy portfolio corrupted")

    # 4. Verify Content (Parsed Data)
    data = result.get('parsed_data', {})
    
    # Check if AAPL entry exists
    if data.get('found'):
        score += 20
        feedback_parts.append("AAPL sell entry found")
        
        # Check Units (tolerance 0.01)
        actual_units = data.get('units', 0.0)
        if abs(actual_units - expected_units) < 0.01:
            score += 20
            feedback_parts.append(f"Units correct ({actual_units})")
        else:
            feedback_parts.append(f"Units incorrect: expected {expected_units}, got {actual_units}")
            
        # Check Price (tolerance 0.01)
        actual_price = data.get('price', 0.0)
        if abs(actual_price - expected_price) < 0.01:
            score += 20
            feedback_parts.append(f"Price correct (${actual_price})")
        else:
            feedback_parts.append(f"Price incorrect: expected {expected_price}, got {actual_price}")
            
        # Check Date String
        actual_date = data.get('date', "")
        # JStock uses "Mar 15, 2024". Check for substring match in case of variations
        if expected_date in actual_date:
            score += 10
            feedback_parts.append(f"Date correct ({actual_date})")
        else:
            feedback_parts.append(f"Date incorrect: expected '{expected_date}', got '{actual_date}'")
            
    else:
        feedback_parts.append("No AAPL sell entry found in CSV")

    # 5. VLM Verification (Trajectory)
    # Ensure the user actually used the UI and didn't just write to the file
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Review these screenshots of a user interacting with JStock software. "
        "The goal was to record a SELL transaction in the Portfolio Management tab. "
        "Do you see the user: "
        "1. Viewing the Portfolio Management tab? "
        "2. Opening a dialog to input transaction details? "
        "3. Entering 'AAPL', '40', or '225.75'? "
        "Return YES if the workflow appears correct, or NO if they never left the main screen or used a terminal."
    )
    
    try:
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt).strip().upper()
        if "YES" in vlm_result:
            score += 15
            feedback_parts.append("VLM: Workflow verified")
        else:
            feedback_parts.append("VLM: UI workflow not clearly visible")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: give points if programmatic checks passed strongly
        if score >= 70:
            score += 15
            feedback_parts.append("VLM: Skipped (programmatic pass)")

    # 6. Final Score Calculation
    passed = score >= 60 and data.get('found') and abs(data.get('units', 0) - expected_units) < 0.01
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }