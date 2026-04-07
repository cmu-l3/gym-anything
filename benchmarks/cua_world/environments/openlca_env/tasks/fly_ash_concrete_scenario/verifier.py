#!/usr/bin/env python3
"""
Verifier for fly_ash_concrete_scenario@1

Verification Logic:
1.  **Database Import & Population (20 pts):**
    - Database exists and is of significant size (>15MB indicates USLCI loaded).
    - Process count > 100.
2.  **Scenario Creation (30 pts):**
    - Verify specific new process exists containing "fly ash" or "30%" in name.
    - Verify `TBL_PRODUCT_SYSTEMS` count >= 1.
3.  **Result Export (30 pts):**
    - File `~/LCA_Results/fly_ash_concrete_lcia.csv` exists.
    - File created/modified *during* the task.
    - File contains expected keywords (impact categories).
4.  **VLM Workflow Verification (20 pts):**
    - Trajectory shows process editor (inputs modification).
    - Trajectory shows calculation/results.

Passing Score: 60/100
"""

import json
import os
import tempfile
import base64
import logging

logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None

def verify_fly_ash_concrete_scenario(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env unavailable"}

    # 1. Retrieve JSON result from container
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    # --- Criterion 1: Database Import (20 pts) ---
    db_size = result.get("db_size_mb", 0)
    process_count = result.get("process_count", 0)
    
    if db_size > 15 and process_count > 100:
        score += 20
        feedback.append("Database imported successfully (USLCI detected).")
    elif db_size > 0:
        score += 10
        feedback.append("Database created but seems small/empty.")
    else:
        feedback.append("No valid database found.")

    # --- Criterion 2: Scenario Process & Product System (30 pts) ---
    fly_ash_proc = result.get("fly_ash_process_found", "")
    ps_count = result.get("product_system_count", 0)
    
    # Check for process name evidence (derby query result)
    # The bash script greps for name, result is the raw SQL output or empty
    if "fly" in fly_ash_proc.lower() or "ash" in fly_ash_proc.lower() or "30%" in fly_ash_proc:
        score += 15
        feedback.append("Custom fly ash process found in database.")
    else:
        feedback.append("Could not confirm specific 'fly ash' process creation in database.")

    if ps_count >= 1:
        score += 15
        feedback.append("Product System created.")
    else:
        feedback.append("No Product System found.")

    # --- Criterion 3: Result Export (30 pts) ---
    file_exists = result.get("file_exists", False)
    fresh_file = result.get("file_created_during_task", False)
    keyword_score = result.get("content_keywords_score", 0)

    if file_exists and fresh_file:
        score += 15
        feedback.append("Result CSV exported.")
        
        # Check content quality
        if keyword_score >= 2:
            score += 15
            feedback.append("CSV content appears valid (keywords found).")
        elif keyword_score == 1:
            score += 8
            feedback.append("CSV content partially verified.")
        else:
            feedback.append("CSV content missing expected keywords (GWP, concrete).")
    elif file_exists:
        # Existed but not modified? (Anti-gaming)
        score += 5
        feedback.append("File exists but timestamp indicates it wasn't created during this task run.")
    else:
        feedback.append("Output CSV not found.")

    # --- Criterion 4: VLM Trajectory Verification (20 pts) ---
    # We want to see the user interacting with the Process Editor (exchanges) 
    # and the Calculation Results.
    
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    if query_vlm:
        # Sample frames
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        
        prompt = """
        You are verifying an OpenLCA task. Look at these screenshots.
        1. Did the user open a "Process" editor (looks like a form with Inputs/Outputs tables)?
        2. Did the user change values in the table (e.g. modifying cement/fly ash amounts)?
        3. Did the user run a calculation (result window with charts/tables)?
        
        Return JSON:
        {
          "process_editor_seen": true/false,
          "calculation_results_seen": true/false,
          "confidence": "low/medium/high"
        }
        """
        
        vlm_res = _vlm_query(query_vlm, prompt, images=frames)
        if vlm_res:
            if vlm_res.get("process_editor_seen"):
                vlm_score += 10
                feedback.append("VLM: Process modification observed.")
            if vlm_res.get("calculation_results_seen"):
                vlm_score += 10
                feedback.append("VLM: Results window observed.")
    else:
        # Fallback if VLM not available but other signals are strong
        if score >= 60:
            vlm_score = 20
            feedback.append("VLM skipped, assuming visual success based on strong programmatic evidence.")
    
    score += vlm_score

    # Final Pass/Fail
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }