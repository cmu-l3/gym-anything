#!/usr/bin/env python3
"""Verifier for underbuilt_parcel_analysis task."""

import json
import tempfile
import os
import math

def verify_underbuilt_parcel_analysis(traj, env_info, task_info):
    """
    Verify the underbuilt parcel analysis task.
    
    Scoring system (100 points):
    - Notebook Executed & Code Quality (15 pts)
    - CSV Valid (10 pts)
    - FAR / Filtering Accuracy vs Ground Truth (35 pts) - CORE
    - JSON Summary Valid (10 pts)
    - JSON Accuracy matches Ground Truth (15 pts)
    - Visualization created (15 pts)
    
    Pass Threshold: 70 points, MUST include some ground truth matching.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Fetch task result metadata
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result:
        return {"passed": False, "score": 0, "feedback": "Result JSON is empty"}

    score = 0
    feedback = []

    # 1. Notebook Execution & Code Quality (15 points)
    nb_data = result.get('notebook', {})
    nb_analysis = nb_data.get('analysis', {})
    
    nb_score = 0
    if nb_data.get('exists') and nb_data.get('modified'):
        nb_score += 5
        num_exec = nb_analysis.get('num_executed_cells', 0)
        if num_exec >= 4:
            nb_score += 5
        elif num_exec > 0:
            nb_score += 2
            
        # Code structure
        if nb_analysis.get('has_groupby') and nb_analysis.get('has_merge'):
            nb_score += 3
        if nb_analysis.get('has_thresholds'):
            nb_score += 2
            
    score += min(15, nb_score)
    feedback.append(f"Notebook: {min(15, nb_score)}/15 pts")

    # 2. CSV Existence & Structure (10 points)
    csv_data = result.get('csv', {})
    csv_score = 0
    if csv_data.get('exists') and csv_data.get('created'):
        csv_score += 5
        # Check rows
        records = csv_data.get('data', [])
        if len(records) > 0:
            csv_score += 5
    score += csv_score
    feedback.append(f"CSV Basic: {csv_score}/10 pts")

    # 3. Ground Truth Matching for CSV (35 points)
    gt = result.get('ground_truth', {})
    gt_zones = gt.get('top_zones', [])
    
    accuracy_score = 0
    if len(gt_zones) > 0 and len(records) > 0:
        # Create dictionaries for fast lookup
        gt_dict = {str(int(row['zone_id'])): row for row in gt_zones if pd_safe_isnotnull(row.get('zone_id'))}
        
        matches = 0
        sqft_matches = 0
        
        for row in records:
            z_id = str(int(float(row.get('zone_id', -999))))
            if z_id in gt_dict:
                matches += 1
                
                # Check metrics with 1% tolerance
                gt_sqft = float(gt_dict[z_id].get('total_soft_site_sqft', 0))
                agt_sqft = float(row.get('total_soft_site_sqft', 0))
                
                if gt_sqft > 0 and abs(agt_sqft - gt_sqft) / gt_sqft <= 0.01:
                    sqft_matches += 1
                    
        # Score calculation: 
        # 15 pts for getting the top zone IDs mostly right
        accuracy_score += min(15, int(15 * (matches / len(gt_dict))))
        # 20 pts for getting the math right (FAR calculation, filtering, aggregation)
        accuracy_score += min(20, int(20 * (sqft_matches / len(gt_dict))))
        
    score += accuracy_score
    feedback.append(f"Data Accuracy: {accuracy_score}/35 pts")

    # 4. JSON Summary valid (10 points)
    json_data = result.get('json_summary', {})
    json_score = 0
    if json_data.get('exists') and json_data.get('created'):
        json_score += 5
        agent_json = json_data.get('data', {})
        if all(k in agent_json for k in ['total_soft_sites_citywide', 'total_soft_site_sqft_citywide', 'top_zone_id']):
            json_score += 5
    score += json_score
    feedback.append(f"JSON Structure: {json_score}/10 pts")

    # 5. JSON Summary Accuracy vs Ground Truth (15 points)
    json_acc_score = 0
    if json_score == 10 and gt:
        agent_json = json_data.get('data', {})
        
        try:
            # Check total count
            if int(agent_json.get('total_soft_sites_citywide', -1)) == gt.get('total_soft_sites_citywide', -2):
                json_acc_score += 5
                
            # Check total sqft (1% tol)
            agt_total = float(agent_json.get('total_soft_site_sqft_citywide', 0))
            gt_total = float(gt.get('total_soft_site_sqft_citywide', 1))
            if gt_total > 0 and abs(agt_total - gt_total) / gt_total <= 0.01:
                json_acc_score += 5
                
            # Check top zone
            if int(agent_json.get('top_zone_id', -1)) == gt.get('top_zone_id', -2):
                json_acc_score += 5
        except (ValueError, TypeError):
            pass
            
    score += json_acc_score
    feedback.append(f"JSON Accuracy: {json_acc_score}/15 pts")

    # 6. Visualization Created (15 points)
    plot_data = result.get('plot', {})
    plot_score = 0
    if plot_data.get('exists'):
        plot_score += 5
        if plot_data.get('created'):
            plot_score += 5
        if plot_data.get('size_kb', 0) >= 5:
            plot_score += 5
    score += plot_score
    feedback.append(f"Plot: {plot_score}/15 pts")

    # VLM Trajectory check to ensure they were actually using the Jupyter interface
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    
    # We will just do a lightweight check on the final screenshot to ensure Jupyter is visible
    final_shot = get_final_screenshot(traj)
    if final_shot and query_vlm:
        vlm_res = query_vlm(
            image=final_shot,
            prompt="Is this a screenshot of a Jupyter Lab environment with code or data visible?"
        )
        if not vlm_res.get('parsed', False) and 'yes' not in str(vlm_res.get('text', '')).lower():
            feedback.append("Warning: VLM could not confirm Jupyter Lab in final screenshot.")

    # Determine Pass/Fail
    passed = score >= 70 and accuracy_score >= 10
    
    if not passed and score >= 70:
        feedback.append("Failed: Did not meet minimum data accuracy threshold.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }

def pd_safe_isnotnull(val):
    if val is None:
        return False
    if isinstance(val, float) and math.isnan(val):
        return False
    return True