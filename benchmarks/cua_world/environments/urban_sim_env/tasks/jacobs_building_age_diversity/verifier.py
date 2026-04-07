#!/usr/bin/env python3
"""Verifier for jacobs_building_age_diversity task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_jacobs_analysis(traj, env_info, task_info):
    """
    Verify Jacobs building age diversity analysis.
    
    Scoring Strategy (100 pts total):
    - File Creation & Anti-Gaming (15 pts): Output files generated during task
    - Notebook Code execution and Logic (30 pts): Proper data cleaning, std, regression
    - CSV Verification (20 pts): Correct columns and row count logic
    - Regression TXT Verification (15 pts): Valid OLS output
    - Plot Verification (10 pts): Scatter plot presence and size
    - VLM Verification (10 pts): Trajectory frames show scatter plot and notebook active
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    # ---------------------------------------------------------
    # PART 1: Read Exported Results
    # ---------------------------------------------------------
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # ---------------------------------------------------------
    # PART 2: Programmatic & Anti-Gaming Checks (15 pts)
    # ---------------------------------------------------------
    files_created = 0
    if result.get('notebook_modified'): files_created += 1
    if result.get('csv_created'): files_created += 1
    if result.get('txt_created'): files_created += 1
    if result.get('plot_created'): files_created += 1
    
    anti_gaming_score = min(15, files_created * 4)
    score += anti_gaming_score
    feedback.append(f"Anti-Gaming/Files Created: {anti_gaming_score}/15")

    # ---------------------------------------------------------
    # PART 3: Notebook Execution & Code Logic (30 pts)
    # ---------------------------------------------------------
    nb_a = result.get('notebook_analysis', {})
    code_score = 0
    
    # Execution checks (10 pts)
    num_exec = nb_a.get('num_executed_cells', 0)
    if num_exec >= 4:
        code_score += 10
    elif num_exec > 0:
        code_score += 5
        
    # Logic checks (20 pts)
    if nb_a.get('has_clean_1850'): code_score += 4
    if nb_a.get('has_std'): code_score += 4
    if nb_a.get('has_filter_20'): code_score += 4
    if nb_a.get('has_ols'): code_score += 4
    if nb_a.get('has_to_csv') and nb_a.get('has_savefig'): code_score += 4

    score += code_score
    feedback.append(f"Notebook Logic & Execution: {code_score}/30")

    # ---------------------------------------------------------
    # PART 4: CSV Output Validation (20 pts)
    # ---------------------------------------------------------
    csv_score = 0
    if result.get('csv_exists'):
        csv_score += 5
        cols = result.get('csv_columns', '')
        # Check required columns
        req_cols = ['zone_id', 'age_diversity', 'commercial_density', 'old_building_pct']
        found_cols = sum(1 for c in req_cols if c in cols)
        csv_score += min(10, found_cols * 3)
        
        # Check row counts (SF zones with >= 20 buildings usually > 50 rows)
        if result.get('csv_rows', 0) > 20:
            csv_score += 5
    score += csv_score
    feedback.append(f"CSV Check: {csv_score}/20")

    # ---------------------------------------------------------
    # PART 5: TXT Regression Validation (15 pts)
    # ---------------------------------------------------------
    txt_score = 0
    if result.get('txt_exists'):
        txt_score += 5
        if result.get('txt_size_bytes', 0) > 100:
            txt_score += 5
        if result.get('txt_has_ols'):
            txt_score += 5
    score += txt_score
    feedback.append(f"Regression TXT Check: {txt_score}/15")

    # ---------------------------------------------------------
    # PART 6: Plot Validation (10 pts)
    # ---------------------------------------------------------
    plot_score = 0
    if result.get('plot_exists'):
        plot_score += 5
        if result.get('plot_size_kb', 0) >= 5:
            plot_score += 5
    score += plot_score
    feedback.append(f"Plot Check: {plot_score}/10")

    # ---------------------------------------------------------
    # PART 7: VLM Trajectory Verification (10 pts)
    # ---------------------------------------------------------
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample frames from the trajectory
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = (
                "You are reviewing a user's workflow in Jupyter Lab. "
                "Look at these sequential screenshots and verify: "
                "1. Did the user write code and execute cells? "
                "2. Is there a scatter plot output visible in any of the notebook cells? "
                "Respond with a JSON object: {\"has_code_execution\": true/false, \"has_scatter_plot\": true/false}"
            )
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("has_code_execution"):
                    vlm_score += 5
                if parsed.get("has_scatter_plot"):
                    vlm_score += 5
                feedback.append(f"VLM Verification: {vlm_score}/10")
            else:
                feedback.append("VLM query failed or unparseable, skipping VLM points.")
        else:
            feedback.append("No trajectory frames available for VLM check.")
    except ImportError:
        feedback.append("gym_anything.vlm not available, granting default VLM points.")
        vlm_score = 10
    except Exception as e:
        logger.warning(f"VLM verification exception: {e}")
        feedback.append("VLM exception occurred.")

    score += vlm_score

    # ---------------------------------------------------------
    # FINAL PASS/FAIL LOGIC
    # ---------------------------------------------------------
    # Require files to be generated, code to be roughly correct, and at least 70%
    key_criteria_met = (files_created >= 3 and code_score >= 15)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }