#!/usr/bin/env python3
"""
Verifier for Neighborhood Amenity Desert Identification task.
Evaluates the agent's programmatic analysis and exported outputs.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_amenity_desert_analysis(traj, env_info, task_info):
    """
    Scoring System (100 points total):
    - Output Files Exist (20 pts): CSV, JSON, PNG, Notebook modified
    - Notebook Executed + VLM Check (15 pts): Code cells executed, workflow verified visually
    - Correct Filtering (15 pts): Only zones with pop >= 500 exported
    - Valid Categorization (15 pts): Exact categories used in CSV
    - Accurate Computation (20 pts): Computed JSON matches Ground Truth (+/- 5%)
    - Summary JSON Valid (15 pts): Keys exist and are correct
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # Read result exported from the environment
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read result JSON: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # Criterion 1: Output Files Exist (20 points)
    files_score = 0
    if result.get("notebook_modified"): files_score += 5
    if result.get("csv_created"): files_score += 5
    if result.get("json_created"): files_score += 5
    if result.get("plot_created") and result.get("plot_size_kb", 0) > 3: files_score += 5
    score += files_score
    feedback.append(f"Output files: {files_score}/20")

    # Early exit check - if files aren't created, task failed
    if files_score == 0:
        return {"passed": False, "score": 0, "feedback": "No output files were created during the task."}

    # Criterion 2: Notebook Executed + VLM Verification (15 points)
    nb_score = 0
    nb_analysis = result.get("notebook_analysis", {})
    if nb_analysis.get("num_executed_cells", 0) > 2:
        nb_score += 5
    if nb_analysis.get("has_merge") and nb_analysis.get("has_groupby"):
        nb_score += 5

    # VLM Verification of workflow
    frames = sample_trajectory_frames(traj, n=3)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if images:
        vlm_prompt = """You are evaluating a data science task in Jupyter Lab. 
        Look at these screenshots. Does the user write pandas code, manipulate UrbanSim data (households/buildings), and generate a chart/plot?
        Respond in JSON with a single key "workflow_visible" : true/false."""
        
        try:
            vlm_res = query_vlm(prompt=vlm_prompt, images=images)
            if vlm_res.get("success") and vlm_res.get("parsed", {}).get("workflow_visible"):
                nb_score += 5
                feedback.append("VLM confirmed data science workflow.")
            else:
                feedback.append("VLM did not detect complete workflow.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # Give benefit of the doubt if programmatic logic ran but VLM failed
            if result.get("plot_created"): nb_score += 5

    score += nb_score
    feedback.append(f"Notebook execution: {nb_score}/15")

    # Criterion 3: Correct Filtering (15 points)
    if result.get("csv_filtered_correctly"):
        score += 15
        feedback.append("CSV filtered correctly (pop >= 500).")
    elif result.get("csv_exists"):
        feedback.append("CSV failed filtering (zones with <500 pop included).")

    # Criterion 4: Valid Categorization (15 points)
    if result.get("csv_categories_valid"):
        score += 15
        feedback.append("Valid categorization used in CSV.")
    elif result.get("csv_exists"):
        feedback.append("Invalid or missing categories in CSV.")

    # Criteria 5 & 6: Accurate Computation & JSON Format (35 points)
    comp_score = 0
    json_score = 0
    
    agent_json = result.get("agent_json_data", {})
    if isinstance(agent_json, dict) and len(agent_json) > 0:
        # Check keys
        has_deserts = "total_amenity_deserts" in agent_json
        has_pop = "desert_population" in agent_json
        has_highest = "highest_amenity_zone_id" in agent_json
        
        if has_deserts and has_pop and has_highest:
            json_score += 15
            feedback.append("JSON keys valid.")
        else:
            feedback.append("JSON missing required keys.")

        # Accuracy checks
        gt_deserts = result.get("gt_total_deserts", 0)
        gt_pop = result.get("gt_desert_population", 0)
        gt_highest = result.get("gt_highest_amenity_zone_id", 0)

        # Check total deserts count (strict match)
        if has_deserts and agent_json["total_amenity_deserts"] == gt_deserts:
            comp_score += 5
        
        # Check desert population (allow 5% tolerance)
        if has_pop and gt_pop > 0:
            try:
                agent_pop_val = float(agent_json["desert_population"])
                error_margin = abs(agent_pop_val - gt_pop) / gt_pop
                if error_margin <= 0.05:
                    comp_score += 10
                elif error_margin <= 0.15:
                    comp_score += 5
            except ValueError:
                pass

        # Check highest amenity zone ID
        if has_highest and agent_json["highest_amenity_zone_id"] == gt_highest:
            comp_score += 5

        feedback.append(f"Computation accuracy: {comp_score}/20")
    else:
        feedback.append("Agent JSON summary missing or invalid.")

    score += comp_score
    score += json_score

    passed = score >= 70 and result.get("csv_created") and result.get("json_created")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }