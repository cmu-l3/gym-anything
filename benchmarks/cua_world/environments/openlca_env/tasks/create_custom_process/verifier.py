#!/usr/bin/env python3
"""
Verifier for Create Custom Process task.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

# VLM Prompts
TRAJECTORY_PROMPT = """You are analyzing an agent's workflow in openLCA.
Goal: Create a new 'Craft beer' process, add inputs (electricity, water, gas), create a product system, and run LCIA.

Observe the screenshots:
1. PROCESS_CREATION: Did the agent open a 'New Process' dialog or form?
2. EXCHANGE_EDITING: Did the agent add items to the 'Inputs/Outputs' tab (e.g., searching for electricity)?
3. PRODUCT_SYSTEM: Did the agent create a product system from the process?
4. CALCULATION: Did the agent run a calculation (result/analysis view)?

Return JSON:
{
  "process_creation_seen": true/false,
  "exchange_editing_seen": true/false,
  "product_system_seen": true/false,
  "calculation_run_seen": true/false,
  "confidence": "high/medium/low"
}
"""

FINAL_STATE_PROMPT = """Analyze the final openLCA state.
Look for:
- A results view (Impact Analysis) showing categories like 'Global Warming'.
- OR a Process Editor tab named 'Craft beer...' with inputs listed.
- OR an open CSV/Excel file with results.

Return JSON:
{
  "results_visible": true/false,
  "process_editor_visible": true/false,
  "relevant_content_found": true/false
}
"""

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm: return None
    try:
        res = query_vlm(prompt=prompt, image=image, images=images)
        if res and res.get("success"): return res.get("parsed", {})
    except: pass
    return None

def verify_create_custom_process(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Load programmatic results
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load results: {e}"}
    finally:
        if os.path.exists(temp.name): os.unlink(temp.name)

    score = 0
    feedback = []

    # 1. Database Verification (Primary Signal) - Max 60 pts
    if result.get("process_created"):
        score += 15
        feedback.append("Process 'Craft beer' created.")
    else:
        feedback.append("Process creation failed.")

    if result.get("exchanges_defined"):
        score += 20
        feedback.append(f"Exchanges defined (Count: {result.get('input_exchange_count')}).")
    elif result.get("input_exchange_count", 0) > 0:
        score += 10
        feedback.append("Some exchanges added, but fewer than required (3).")
    
    if result.get("product_system_created"):
        score += 15
        feedback.append("Product system created.")

    if result.get("lcia_methods_present"):
        score += 5
        feedback.append("LCIA methods available.")

    # 2. File Output Verification - Max 30 pts
    if result.get("file_exists") != "false":
        if result.get("file_created_during_task"):
            score += 10
            feedback.append("Result file created.")
            if result.get("has_gwp_keyword"):
                score += 20
                feedback.append("Result file contains valid GWP data.")
            else:
                score += 5
                feedback.append("Result file missing expected keywords.")
        else:
            feedback.append("Result file is stale (not created during task).")

    # 3. VLM Verification - Max 10 pts
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, 5)
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        
        vlm_score = 0
        if vlm_res:
            if vlm_res.get("process_creation_seen"): vlm_score += 2
            if vlm_res.get("exchange_editing_seen"): vlm_score += 3
            if vlm_res.get("product_system_seen"): vlm_score += 3
            if vlm_res.get("calculation_run_seen"): vlm_score += 2
        
        score += vlm_score
        if vlm_score > 0:
            feedback.append(f"VLM verified workflow ({vlm_score} pts).")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }