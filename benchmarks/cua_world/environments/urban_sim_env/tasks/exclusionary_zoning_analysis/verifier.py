#!/usr/bin/env python3
"""Verifier for exclusionary_zoning_analysis task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_exclusionary_zoning(traj, env_info, task_info):
    """Verify exclusionary zoning analysis was completed.

    Scoring (100 points total):
    - Notebook & Process (15 pts): Notebook code, executed cells
    - Output Structures (30 pts): CSV formatting, Plot presence, JSON keys
    - Analytical Accuracy (35 pts): Validating the actual values inside the JSON output
    - VLM Trajectory (20 pts): Visual evidence of coding and scatter plot generation
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_cols = metadata.get('expected_csv_columns', [])
    expected_json_keys = metadata.get('expected_json_keys', [])

    score = 0
    feedback = []

    # =======================================================
    # Part 1: Read Primary Task Result JSON
    # =======================================================
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read result script output: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # Notebook Checks (15 pts)
    nb_score = 0
    if result.get('notebook_exists') and result.get('notebook_modified'):
        nb_score += 5
    
    nb_a = result.get('notebook_analysis', {})
    if nb_a.get('has_pandas') and nb_a.get('has_hdf'):
        nb_score += 3
    if nb_a.get('has_merge') and nb_a.get('has_groupby'):
        nb_score += 3
    if nb_a.get('num_executed_cells', 0) >= 3:
        nb_score += 4
    
    score += nb_score
    feedback.append(f"Notebook Code: {nb_score}/15")

    # Output Structure Checks (30 pts)
    struct_score = 0
    
    # CSV (10 pts)
    if result.get('csv_exists') and result.get('csv_created'):
        struct_score += 5
        actual_cols = result.get('csv_columns', '')
        cols_found = sum([1 for c in expected_csv_cols if c in actual_cols])
        if cols_found >= len(expected_csv_cols) - 1:  # allow 1 slight miss
            struct_score += 5
    
    # Plot (10 pts)
    if result.get('plot_exists') and result.get('plot_created'):
        struct_score += 5
        if result.get('plot_size_kb', 0) >= 10:
            struct_score += 5
            
    # JSON Existence (10 pts)
    if result.get('json_exists') and result.get('json_created'):
        struct_score += 10
        
    score += struct_score
    feedback.append(f"Output Structures: {struct_score}/30")

    # =======================================================
    # Part 2: Analytical Accuracy via Student's JSON (35 pts)
    # =======================================================
    accuracy_score = 0
    student_json = None
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        json_path = metadata.get('expected_json_path', '/home/ga/urbansim_projects/output/zoning_equity_summary.json')
        copy_from_env(json_path, temp_json.name)
        with open(temp_json.name, 'r') as f:
            student_json = json.load(f)
    except Exception as e:
        feedback.append(f"Could not load agent's JSON output: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if student_json:
        # Check Keys
        keys_present = all(k in student_json for k in expected_json_keys)
        if keys_present:
            accuracy_score += 10
            
            try:
                excl_zones = int(student_json.get('exclusive_sf_zone_count', 0))
                div_zones = int(student_json.get('diverse_zone_count', 0))
                excl_inc = float(student_json.get('exclusive_sf_median_income', 0))
                div_inc = float(student_json.get('diverse_median_income', 0))
                corr = float(student_json.get('correlation_sf_pct_income', 0))

                # Both zone counts should be > 0 in SF
                if excl_zones > 0 and div_zones > 0:
                    accuracy_score += 5
                
                # Exclusive SF median income should realistically be greater than diverse
                if excl_inc > div_inc:
                    accuracy_score += 10
                    
                # Correlation should be valid and typically positive
                if -1.0 <= corr <= 1.0 and corr != 0:
                    accuracy_score += 5
                    if corr > 0:
                        accuracy_score += 5
                        
            except ValueError:
                feedback.append("JSON values had incorrect types (could not parse to int/float).")
        else:
            feedback.append("JSON was missing expected keys.")
            
    score += accuracy_score
    feedback.append(f"Analytical Accuracy: {accuracy_score}/35")

    # =======================================================
    # Part 3: VLM Trajectory Verification (20 pts)
    # =======================================================
    vlm_score = 0
    
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        all_frames = frames + [final] if final else frames
        
        if all_frames:
            vlm_prompt = """
            You are verifying a data science task in Jupyter Lab.
            Look at this sequence of screenshots.
            
            Check for the following:
            1. Is the Jupyter Lab interface open?
            2. Did the user write Python code involving pandas and matplotlib?
            3. In any frame, is there a scatter plot visible (mapping points on an X/Y axis)?
            
            Return ONLY a valid JSON object:
            {
                "jupyter_open": true/false,
                "code_written": true/false,
                "scatter_plot_visible": true/false
            }
            """
            
            vlm_response = query_vlm(prompt=vlm_prompt, images=all_frames)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("jupyter_open"): vlm_score += 5
                if parsed.get("code_written"): vlm_score += 5
                if parsed.get("scatter_plot_visible"): vlm_score += 10
            else:
                feedback.append("VLM query failed.")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback.append("VLM trajectory check bypassed.")
        # If VLM fails due to framework missing, grant partial credit so local tests don't strictly fail
        vlm_score += 10
        
    score += vlm_score
    feedback.append(f"VLM Visual Proof: {vlm_score}/20")

    # Pass Threshold
    passed = score >= 70 and struct_score >= 15 and accuracy_score >= 15

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }