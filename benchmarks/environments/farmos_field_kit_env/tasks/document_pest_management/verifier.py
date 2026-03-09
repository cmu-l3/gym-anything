#!/usr/bin/env python3
"""
Verifier for document_pest_management task.

This task requires the agent to create two specific logs (Observation and Input)
in the farmOS Field Kit Android app.

Verification Strategy:
1. VLM Trajectory Analysis (Primary):
   - Scans trajectory for creation of Observation log with specific pest details.
   - Scans trajectory for creation of Input log with specific treatment details.
   - Verifies sequential workflow.

2. UI State Analysis (Secondary):
   - Checks final screenshot/UI dump to confirm at least two logs are visible in the list.
   - Checks if app was left open.
"""

import json
import os
import logging
import tempfile
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pest_management(traj, env_info, task_info):
    """
    Verify creation of pest observation and treatment input logs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve artifacts from environment
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    final_screenshot_path = os.path.join(temp_dir, "task_final.png")
    ui_dump_path = os.path.join(temp_dir, "ui_dump.xml")
    
    try:
        copy_from_env("/sdcard/task_result.json", result_json_path)
        copy_from_env("/sdcard/task_final.png", final_screenshot_path)
        # UI dump might fail if app crashed, so we wrap it
        try:
            copy_from_env("/sdcard/ui_dump.xml", ui_dump_path)
        except Exception:
            logger.warning("Could not copy UI dump")
            ui_dump_path = None
            
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task artifacts: {str(e)}"}

    # 2. VLM Trajectory Verification
    # This is critical because we can't easily query the Android SQLite DB from here
    # to check the specific text content of the logs.
    
    frames = sample_trajectory_frames(traj, n=12)
    # Add final screenshot to frames for analysis
    if os.path.exists(final_screenshot_path):
        frames.append(final_screenshot_path)

    prompt = f"""
    You are verifying an Android agent task. The agent was supposed to create TWO logs in farmOS Field Kit:
    
    1. An OBSERVATION log:
       - Date: {metadata.get('observation_date')}
       - Notes should contain: "Aphid", "soybean", "Field B", "30%"
       
    2. An INPUT log:
       - Date: {metadata.get('input_date')}
       - Notes should contain: "neem oil", "2%", "4 liters"
       - Quantity: "12" liters
       
    Analyze the screenshots sequence to answer:
    1. Did the agent create an OBSERVATION log? (Look for 'Observation' type selection and aphid text)
    2. Did the agent create an INPUT log? (Look for 'Input' type selection and neem oil text)
    3. Did the agent enter the quantity '12' for the input log?
    4. Did the agent set the dates to November 15, 2024?
    5. In the final state (last image), are there two items visible in the list?
    
    Respond in JSON:
    {{
        "created_observation": true/false,
        "observation_details_correct": true/false,
        "created_input": true/false,
        "input_details_correct": true/false,
        "quantity_correct": true/false,
        "dates_correct": true/false,
        "final_list_shows_two_logs": true/false,
        "reasoning": "..."
    }}
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    # Fallback if VLM fails
    if not vlm_result.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed to process images."}
        
    analysis = vlm_result.get("parsed", {})
    logger.info(f"VLM Analysis: {analysis}")

    # 3. Scoring
    score = 0
    feedback_parts = []
    
    # Observation Log (35 pts)
    if analysis.get("created_observation"):
        score += 15
        feedback_parts.append("Observation log created.")
        if analysis.get("observation_details_correct"):
            score += 15
            feedback_parts.append("Observation details match.")
        if analysis.get("dates_correct"): # Shared points for date
            score += 5
    else:
        feedback_parts.append("Failed to create Observation log.")

    # Input Log (45 pts)
    if analysis.get("created_input"):
        score += 15
        feedback_parts.append("Input log created.")
        if analysis.get("input_details_correct"):
            score += 15
            feedback_parts.append("Input details match.")
        if analysis.get("quantity_correct"):
            score += 10
            feedback_parts.append("Quantity correct.")
        if analysis.get("dates_correct") and score < 75: # Don't double count date too much
            score += 5
    else:
        feedback_parts.append("Failed to create Input log.")

    # Final State (20 pts)
    # Check VLM + UI Dump
    ui_dump_valid = False
    if ui_dump_path and os.path.exists(ui_dump_path):
        try:
            with open(ui_dump_path, 'r') as f:
                content = f.read()
                # Simple check: do we see keywords in the final list UI?
                # The list usually shows Date and Type
                if "Observation" in content and "Input" in content:
                    ui_dump_valid = True
                # Or count list items (ListView children) - hard to do reliably with regex on XML
                # Rely on VLM for visual count
        except:
            pass

    if analysis.get("final_list_shows_two_logs") or ui_dump_valid:
        score += 20
        feedback_parts.append("Final list shows created logs.")
    else:
        feedback_parts.append("Final list does not clearly show both logs.")

    # Anti-gaming: App must be running
    if result_data.get("app_running", False):
        pass # No points, just a requirement? Let's just deduct if not running?
             # Actually, we usually give points for state.
             # Let's say if score > 0 but app crashed, we might penalize.
             # But VLM usually covers this.
    else:
        feedback_parts.append("(Warning: App was not running at end)")

    passed = score >= 60 and analysis.get("created_observation") and analysis.get("created_input")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }