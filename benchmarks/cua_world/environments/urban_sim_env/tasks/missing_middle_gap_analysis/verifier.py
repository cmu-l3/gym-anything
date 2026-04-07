#!/usr/bin/env python3
"""Verifier for missing_middle_gap_analysis task."""

import json
import tempfile
import os
import re

def verify_missing_middle(traj, env_info, task_info):
    """Verify missing middle analysis was completed successfully.

    Scoring (100 points total):
    - File Existence & Notebook Execution (20 pts)
    - CSV Formatting & Columns (15 pts)
    - Data Logic - Unit Summation / Ground Truth (25 pts)
    - Data Logic - Math & Flagging Consistency (20 pts)
    - VLM Trajectory Verification (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_columns = metadata.get('expected_csv_columns', [])
    score = 0
    feedback = []

    # ---------------------------------------------------------
    # 1. Read task result JSON
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
    # 2. File Existence & Notebook Execution (20 pts)
    # ---------------------------------------------------------
    if result.get('notebook_exists') and result.get('notebook_modified'):
        score += 5
        nb_a = result.get('notebook_analysis', {})
        if nb_a.get('has_code') and nb_a.get('num_executed_cells', 0) > 0:
            score += 5
            feedback.append("Notebook executed successfully.")
        else:
            feedback.append("Notebook not fully executed.")
    else:
        feedback.append("Notebook not found or modified.")

    if result.get('plot_exists') and result.get('plot_created'):
        if result.get('plot_size_kb', 0) >= 5:
            score += 10
            feedback.append("Plot created successfully.")
        else:
            score += 5
            feedback.append("Plot created but file size is suspiciously small.")
    else:
        feedback.append("Plot not created.")

    # ---------------------------------------------------------
    # 3. CSV Formatting & Columns (15 pts)
    # ---------------------------------------------------------
    csv_exists = result.get('csv_exists', False)
    if csv_exists and result.get('csv_created'):
        score += 5
        actual_cols = [c.lower().strip() for c in result.get('csv_columns', [])]
        expected_cols_lower = [c.lower().strip() for c in expected_columns]
        
        # Check if all expected columns are present
        missing_cols = [c for c in expected_cols_lower if c not in actual_cols]
        if not missing_cols:
            score += 10
            feedback.append("CSV has all required columns.")
        else:
            feedback.append(f"CSV missing columns: {missing_cols}")
    else:
        feedback.append("CSV output not created.")

    # ---------------------------------------------------------
    # 4. Data Logic - Math & Consistency (20 pts)
    # ---------------------------------------------------------
    if csv_exists:
        if result.get('logic_percentages_sum_to_100'):
            score += 10
            feedback.append("Percentages sum to 100 correctly.")
        else:
            feedback.append("Percentages do not sum to 100 (math error).")

        if result.get('logic_flag_correct'):
            score += 10
            feedback.append("Opportunity zone flag logic is correct.")
        else:
            feedback.append("Opportunity zone flag logic is incorrect.")

    # ---------------------------------------------------------
    # 5. Data Logic - Ground Truth / Unit Summation (25 pts)
    # ---------------------------------------------------------
    if csv_exists:
        if result.get('logic_gt_units_match'):
            score += 25
            feedback.append("Total units match ground truth (correctly summed units, didn't just count buildings).")
        else:
            # Check if notebook at least attempted a sum
            nb_a = result.get('notebook_analysis', {})
            if nb_a.get('has_sum'):
                score += 10
                feedback.append("Total units do not match ground truth, but .sum() was used in code (partial credit).")
            else:
                feedback.append("Total units do not match ground truth (likely counted buildings instead of summing units).")

    # ---------------------------------------------------------
    # 6. VLM Trajectory Verification (20 pts)
    # ---------------------------------------------------------
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames

        if images:
            prompt = """You are analyzing an AI agent doing data science in Jupyter Lab.
Look at these sequential screenshots. 
Did the agent write code to categorize housing units, compute percentages, and generate a stacked bar chart?
Is there a chart visible in the final outputs showing housing breakdowns?

Respond in JSON format:
{
    "wrote_analysis_code": true/false,
    "chart_generated": true/false
}"""
            vlm_result = query_vlm(prompt=prompt, images=images)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("wrote_analysis_code"):
                    score += 10
                if parsed.get("chart_generated"):
                    score += 10
                feedback.append("VLM visual verification completed.")
            else:
                feedback.append("VLM query failed or format incorrect.")
    except Exception as e:
        feedback.append(f"VLM verification skipped/errored: {str(e)}")

    # ---------------------------------------------------------
    # Final Evaluation
    # ---------------------------------------------------------
    key_criteria_met = result.get('csv_exists', False) and result.get('logic_gt_units_match', False)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }