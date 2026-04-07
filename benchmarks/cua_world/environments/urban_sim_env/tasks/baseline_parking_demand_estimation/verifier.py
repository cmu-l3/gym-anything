#!/usr/bin/env python3
"""Verifier for baseline_parking_demand_estimation task."""

import json
import tempfile
import os
import re

def verify_parking_demand(traj, env_info, task_info):
    """
    Verify the parking demand analysis was completed correctly.
    
    Scoring System (100 pts):
    - Notebook Execution: 10 pts
    - Output Data Integrity (CSV sorted, columns exist): 20 pts
    - Building Multiplier Logic (row math correct): 20 pts
    - Parcel Area Aggregation (Double Counting check): 25 pts
    - Density Calculation (spaces_per_acre correct): 10 pts
    - Visualization Generated (PNG exists): 5 pts
    - JSON Summary Correctness: 10 pts
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_columns = metadata.get('expected_csv_columns', [
        "zone_id", "residential_spaces", "non_residential_spaces", 
        "total_spaces", "total_parcel_acres", "spaces_per_acre"
    ])
    
    score = 0
    feedback = []

    # Read the exported task result
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

    # 1. Notebook Execution (10 pts)
    nb_a = result.get('notebook_analysis', {})
    num_exec = nb_a.get('num_executed_cells', 0)
    if result.get('notebook_exists') and num_exec > 0:
        if num_exec >= 4:
            score += 10
            feedback.append("Notebook executed successfully.")
        else:
            score += 5
            feedback.append("Notebook partially executed.")
    else:
        feedback.append("Notebook missing or not executed.")

    # 2. Output Data Integrity (20 pts)
    csv_exists = result.get('csv_exists', False)
    if csv_exists:
        cols = result.get('csv_columns', [])
        missing_cols = [c for c in expected_columns if c not in cols]
        
        if not missing_cols:
            score += 10
            feedback.append("CSV contains all required columns.")
        else:
            feedback.append(f"CSV missing columns: {missing_cols}")
            
        if result.get('is_sorted', False):
            score += 10
            feedback.append("CSV is correctly sorted by total_spaces.")
        else:
            feedback.append("CSV is not sorted descending by total_spaces.")
    else:
        feedback.append("CSV output not found.")

    # 3. Building Multiplier Logic (20 pts)
    if csv_exists and not missing_cols:
        math_err = result.get('multiplier_math_max_error', 9999.0)
        if math_err < 0.1:
            score += 20
            feedback.append("Total spaces strictly equals Res + Non-Res spaces.")
        else:
            feedback.append(f"Math error in total spaces sum (max diff: {math_err}).")

    # 4. Parcel Area Aggregation / Double Counting Check (25 pts)
    # True parcel acres for SF is ~25k. Joining buildings inflates this if they do .sum() naively.
    true_acres = result.get('true_total_acres', 0.0)
    agent_acres = result.get('agent_total_acres', 0.0)
    
    if csv_exists and agent_acres > 0:
        # Give a small buffer (50%) for potential filtering differences, but a double count
        # usually inflates the acreage by 300%+ (many buildings per parcel in SF).
        if agent_acres <= (true_acres * 1.5):
            score += 25
            feedback.append(f"Avoided double-counting land area (Agent acres: {agent_acres:.0f}, True: {true_acres:.0f}).")
        else:
            feedback.append(f"FAILED double-counting check. Land area inflated (Agent acres: {agent_acres:.0f}, True: {true_acres:.0f}).")
    else:
        feedback.append("Could not evaluate double-counting (invalid acreage sums).")

    # 5. Density Calculation (10 pts)
    if csv_exists and not missing_cols:
        den_err = result.get('density_math_max_error', 9999.0)
        if den_err < 0.1:
            score += 10
            feedback.append("Density math (spaces_per_acre) is correct.")
        else:
            feedback.append(f"Density calculation incorrect (max diff: {den_err}).")

    # 6. Visualization Generated (5 pts)
    if result.get('plot_exists') and result.get('plot_size_kb', 0) > 5:
        score += 5
        feedback.append("Plot created successfully.")
    else:
        feedback.append("Plot missing or invalid.")

    # 7. JSON Summary Correctness (10 pts)
    if result.get('json_exists'):
        json_keys = result.get('json_keys', [])
        required_keys = ["citywide_residential_spaces", "citywide_non_residential_spaces", "citywide_total_spaces"]
        if all(k in json_keys for k in required_keys):
            j_res = result.get('json_res', 0)
            j_non = result.get('json_non_res', 0)
            j_tot = result.get('json_total', 0)
            
            if abs(j_tot - (j_res + j_non)) < 0.1 and j_tot > 0:
                score += 10
                feedback.append("JSON summary exists with correct math.")
            else:
                feedback.append("JSON summary math is incorrect.")
        else:
            feedback.append("JSON summary missing required keys.")
    else:
        feedback.append("JSON summary missing.")

    # Trajectory / VLM verification (Optional supplementary check via imports if needed, 
    # but programmatic checks here are extremely robust due to data invariants).
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
    
    # We perform a quick VLM check to ensure the plot is actually a stacked bar chart
    if result.get('plot_exists') and query_vlm:
        final_frame = None
        try:
            # Check the last 3 frames to see if the chart was displayed
            frames = sample_trajectory_frames(traj, n=3)
            if frames:
                prompt = """Is there a stacked bar chart visible on the screen? 
                (A bar chart where each bar is split into two or more colors representing different categories).
                Answer ONLY with 'yes' or 'no'."""
                vlm_ans = query_vlm(images=frames, prompt=prompt)
                if vlm_ans and "yes" in str(vlm_ans.get("response", "")).lower():
                    feedback.append("VLM verified stacked bar chart presence.")
        except Exception as e:
            pass

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }