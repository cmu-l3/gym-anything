#!/usr/bin/env python3
"""
Verifier for create_instrument_list task in NinjaTrader.

Verifies that the agent created a persistent Instrument List XML file
containing the required instruments.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Path inside the container (Windows path mapped)
# Note: The 'copy_from_env' tool handles the retrieval from the container.
# The export script writes to C:\Users\Docker\Desktop\NinjaTraderTasks\create_instrument_list_result.json
CONTAINER_RESULT_PATH = "C:/Users/Docker/Desktop/NinjaTraderTasks/create_instrument_list_result.json"

def verify_create_instrument_list(traj, env_info, task_info):
    """
    Verify creation of NinjaTrader instrument list.
    
    Scoring Criteria:
    1. List file exists (20 pts)
    2. List created/modified during task (Anti-gaming) (20 pts)
    3. Contains SPY (20 pts)
    4. Contains AAPL (20 pts)
    5. Contains MSFT (20 pts)
    
    Pass Threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp file for extraction
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        # 1. Retrieve Result JSON
        try:
            copy_from_env(CONTAINER_RESULT_PATH, temp_path)
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve or parse task result: {str(e)}"
            }
        
        # 2. Evaluate Criteria
        score = 0
        feedback_parts = []
        
        # Criterion 1: File Exists
        if result.get('file_exists', False):
            score += 20
            feedback_parts.append("Instrument list file created (+20)")
        else:
            feedback_parts.append("Instrument list file NOT found (0)")
            return {"passed": False, "score": 0, "feedback": "Instrument List file was not created."}

        # Criterion 2: Timestamp Check (Anti-gaming)
        if result.get('created_during_task', False):
            score += 20
            feedback_parts.append("File modified during task session (+20)")
        else:
            feedback_parts.append("File detected but timestamp indicates it is old/stale (0)")
            # If the file wasn't modified during the task, we shouldn't award points for its content
            return {
                "passed": False, 
                "score": score, 
                "feedback": " | ".join(feedback_parts) + " (Anti-gaming check failed: File not modified)"
            }

        # Criteria 3-5: Instrument Content
        instruments = result.get('instruments_found', [])
        
        if "SPY" in instruments:
            score += 20
            feedback_parts.append("SPY found (+20)")
        else:
            feedback_parts.append("SPY missing")
            
        if "AAPL" in instruments:
            score += 20
            feedback_parts.append("AAPL found (+20)")
        else:
            feedback_parts.append("AAPL missing")
            
        if "MSFT" in instruments:
            score += 20
            feedback_parts.append("MSFT found (+20)")
        else:
            feedback_parts.append("MSFT missing")

        # Final Assessment
        passed = score >= 70
        
        # Optional: Add VLM check here if needed for trajectory verification
        # For this specific task, file persistence is a strong enough signal.
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)