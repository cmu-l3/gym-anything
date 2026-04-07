#!/usr/bin/env python3
"""
Verifier for nonres_space_utilization task.
Evaluates agent's data joining, metric calculations, filtering, and plotting capabilities.
"""

import json
import tempfile
import os
import math

def verify_space_utilization(traj, env_info, task_info):
    """
    Scoring Rubric (100 points total):
    - CSV Exists & Valid Structure: 15
    - Correct Zone Count: 10
    - Citywide Totals Accurate: 15
    - Median sqft/job Accurate: 15
    - Top 5 Efficient Zones Match: 15
    - Sort Order Correct: 5
    - Scatter Plot Valid PNG: 10
    - Notebook Executed: 10
    - Code Patterns Present: 5
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0
    max_score = 100

    # 1. Load results and ground truth
    agent_result = None
    gt_result = None

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            agent_result = json.load(f)
            
        copy_from_env("/tmp/ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read result or ground truth files: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    if agent_result is None or gt_result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # Check anti-gaming (file creation timestamps)
    if not agent_result.get("notebook_created_during_task") and agent_result.get("notebook_exists"):
        feedback.append("Warning: Notebook appears to predate the task start time.")
    if not agent_result.get("csv_created_during_task") and agent_result.get("csv_exists"):
        feedback.append("Warning: CSV appears to predate the task start time.")

    # 2. CSV Exists & Valid Structure (15 points)
    csv_valid = False
    if agent_result.get("csv_exists"):
        if agent_result.get("csv_has_required_cols"):
            score += 15
            csv_valid = True
            feedback.append("CSV exists and has required columns (+15)")
        else:
            score += 5
            feedback.append("CSV exists but is missing required columns (+5)")
    else:
        feedback.append("Output CSV not found")

    if csv_valid:
        # 3. Correct Zone Count (10 points)
        agent_zones = agent_result.get("agent_num_zones", 0)
        gt_zones = gt_result.get("num_zones", -1)
        if abs(agent_zones - gt_zones) <= 2:
            score += 10
            feedback.append(f"Zone count correct: {agent_zones} (+10)")
        else:
            feedback.append(f"Zone count incorrect. Expected ~{gt_zones}, got {agent_zones}")

        # 4. Citywide Totals Accurate (15 points)
        agent_sqft = agent_result.get("agent_total_non_res_sqft", 0)
        gt_sqft = gt_result.get("total_non_res_sqft", 1)
        agent_jobs = agent_result.get("agent_total_jobs", 0)
        gt_jobs = gt_result.get("total_jobs", 1)
        
        sqft_error = abs(agent_sqft - gt_sqft) / gt_sqft
        jobs_error = abs(agent_jobs - gt_jobs) / gt_jobs
        
        if sqft_error <= 0.01 and jobs_error <= 0.01:
            score += 15
            feedback.append("Citywide totals (sqft & jobs) accurate (+15)")
        elif sqft_error <= 0.10 and jobs_error <= 0.10:
            score += 7
            feedback.append("Citywide totals partially accurate (+7)")
        else:
            feedback.append("Citywide totals inaccurate")

        # 5. Median sqft/job Accurate (15 points)
        agent_median = agent_result.get("agent_median_sqft_per_job", 0)
        gt_median = gt_result.get("median_sqft_per_job", 1)
        median_error = abs(agent_median - gt_median) / gt_median
        
        if median_error <= 0.10:
            score += 15
            feedback.append("Median sqft/job computation accurate (+15)")
        else:
            feedback.append(f"Median sqft/job inaccurate. Expected ~{gt_median:.2f}, got {agent_median:.2f}")

        # 6. Top 5 Efficient Zones Match (15 points)
        agent_top_5 = agent_result.get("agent_top_5_zones", [])
        gt_top_5 = gt_result.get("top_5_zones", [])
        matches = len(set(agent_top_5).intersection(set(gt_top_5)))
        
        if matches >= 4:
            score += 15
            feedback.append(f"Top 5 most efficient zones match ({matches}/5) (+15)")
        elif matches >= 2:
            score += 7
            feedback.append(f"Top 5 most efficient zones partially match ({matches}/5) (+7)")
        else:
            feedback.append(f"Top 5 most efficient zones incorrect ({matches}/5 matched)")

        # 7. Sort Order Correct (5 points)
        if agent_result.get("agent_is_sorted"):
            score += 5
            feedback.append("CSV is sorted correctly (+5)")
        else:
            feedback.append("CSV is not sorted ascending by sqft_per_job")

    # 8. Scatter Plot Valid PNG (10 points)
    if agent_result.get("plot_exists"):
        size_kb = agent_result.get("plot_size_kb", 0)
        if size_kb >= 5:
            score += 10
            feedback.append(f"Scatter plot valid PNG created ({size_kb:.1f} KB) (+10)")
        else:
            score += 3
            feedback.append(f"Plot created but file size too small ({size_kb:.1f} KB) (+3)")
    else:
        feedback.append("Scatter plot not found")

    # 9. Notebook Executed (10 points)
    nb = agent_result.get("notebook_analysis", {})
    num_exec = nb.get("num_executed", 0)
    has_errors = nb.get("has_errors", True)
    
    if num_exec >= 4 and not has_errors:
        score += 10
        feedback.append("Notebook successfully executed without errors (+10)")
    elif num_exec > 0:
        score += 5
        feedback.append(f"Notebook partially executed ({num_exec} cells) or had errors (+5)")
    else:
        feedback.append("Notebook was not executed")

    # 10. Code Patterns Present (5 points)
    patterns_found = sum([
        nb.get("has_read_hdf", False),
        nb.get("has_merge", False),
        nb.get("has_groupby", False),
        nb.get("has_scatter", False),
        nb.get("has_to_csv", False)
    ])
    
    if patterns_found >= 4:
        score += 5
        feedback.append("Appropriate code analysis patterns found (+5)")
    elif patterns_found >= 2:
        score += 2
        feedback.append("Some code analysis patterns found (+2)")

    # Optional VLM verification step via trajectory (anti-gaming)
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    try:
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            prompt = "Is the user interacting with a Jupyter notebook interface to write pandas code or view data tables? Answer YES or NO."
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and vlm_response.get("parsed"):
                # If VLM confirms trajectory is real work, ensure we don't zero out.
                # Primarily used to ensure agent isn't just placing pre-computed files.
                pass
    except Exception as e:
        # Fail gracefully if VLM is unavailable
        pass

    passed = score >= 60 and csv_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }