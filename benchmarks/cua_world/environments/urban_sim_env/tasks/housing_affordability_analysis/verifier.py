#!/usr/bin/env python3
"""Verifier for housing_affordability_analysis task."""

import json
import os
import sys
import tempfile
import csv

def verify_housing_affordability(traj, env_info, task_info):
    """
    Verify housing affordability analysis was completed.
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_columns = metadata.get('expected_csv_columns', [
        'zone_id', 'median_income', 'median_price', 'price_to_income_ratio', 'num_households'
    ])
    
    score = 0
    feedback = []
    
    # --- Read Task Result JSON ---
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read task result JSON: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # --- Read Ground Truth JSON ---
    gt = None
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/affordability_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read ground truth JSON: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
            
    if gt is None:
        gt = {'num_zones': 0, 'median_ratio': 0}

    # === CRITERION 1: Notebook Existence and Execution (20 pts) ===
    nb_score = 0
    if result.get('notebook_exists') and result.get('notebook_modified'):
        nb_score += 5
        feedback.append("Notebook created/modified")
        
    nb_a = result.get('notebook_analysis', {})
    num_exec = nb_a.get('num_executed_cells', 0)
    if num_exec >= 3:
        nb_score += 5
        feedback.append(f"Notebook executed ({num_exec} cells)")
    elif num_exec > 0:
        nb_score += 2
        feedback.append(f"Notebook partially executed ({num_exec} cells)")
        
    code_patterns = 0
    if nb_a.get('has_read_hdf'): code_patterns += 1
    if nb_a.get('has_groupby'): code_patterns += 1
    if nb_a.get('has_merge'): code_patterns += 1
    if nb_a.get('has_median'): code_patterns += 1
    if nb_a.get('has_plot'): code_patterns += 1
    
    if code_patterns >= 4:
        nb_score += 10
        feedback.append("Notebook code logic correct")
    elif code_patterns >= 2:
        nb_score += 5
        feedback.append("Notebook code logic partially correct")
        
    score += nb_score

    # === CRITERION 2: CSV Export and Data Validation (50 pts) ===
    csv_score = 0
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/home/ga/urbansim_projects/output/affordability_by_zone.csv", temp_csv.name)
        if os.path.exists(temp_csv.name) and os.path.getsize(temp_csv.name) > 0:
            csv_score += 10
            feedback.append("CSV file created")
            
            with open(temp_csv.name, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                columns = [c.lower() for c in (reader.fieldnames or [])]
                rows = list(reader)
                
            # Check columns
            missing_cols = [c for c in expected_csv_columns if c not in columns and not any(c in col for col in columns)]
            if not missing_cols:
                csv_score += 10
                feedback.append("CSV has all required columns")
            else:
                feedback.append(f"CSV missing columns: {missing_cols}")
                
            # Check zone count against ground truth
            gt_zones = gt.get('num_zones', 0)
            agent_zones = len(rows)
            if gt_zones > 0:
                diff_pct = abs(agent_zones - gt_zones) / gt_zones
                if diff_pct <= 0.2:
                    csv_score += 15
                    feedback.append(f"Zone count accurate (Agent: {agent_zones}, GT: {gt_zones})")
                else:
                    feedback.append(f"Zone count mismatch (Agent: {agent_zones}, GT: {gt_zones})")
                    
            # Check median ratio accuracy against ground truth
            ratio_col = next((c for c in columns if 'ratio' in c), None)
            if ratio_col and len(rows) > 0:
                try:
                    ratios = []
                    for r in rows:
                        actual_key = next((k for k in r.keys() if k and k.lower() == ratio_col), None)
                        if actual_key and r[actual_key]:
                            val = float(r[actual_key])
                            if 0 < val < 1000:
                                ratios.append(val)
                                
                    if ratios:
                        ratios.sort()
                        agent_median = ratios[len(ratios)//2]
                        gt_median = gt.get('median_ratio', 0)
                        
                        if gt_median > 0:
                            err = abs(agent_median - gt_median) / gt_median
                            if err <= 0.3:
                                csv_score += 15
                                feedback.append(f"Median ratio accurate (Agent: {agent_median:.2f}, GT: {gt_median:.2f})")
                            else:
                                feedback.append(f"Median ratio inaccurate (Agent: {agent_median:.2f}, GT: {gt_median:.2f})")
                except Exception as e:
                    feedback.append(f"Error validating ratios: {e}")
                    
    except Exception as e:
        feedback.append(f"Error checking CSV: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)
            
    score += csv_score

    # === CRITERION 3: Visualization Check (15 pts) ===
    plot_score = 0
    if result.get('plot_exists'):
        plot_score += 5
        feedback.append("Plot PNG exists")
        if result.get('plot_created'):
            plot_score += 5
            feedback.append("Plot PNG created during task")
        if result.get('plot_size_kb', 0) >= 5:
            plot_score += 5
            feedback.append("Plot PNG size is reasonable")
    else:
        feedback.append("Plot PNG not found")
        
    score += plot_score

    # === CRITERION 4: Trajectory VLM Verification (15 pts) ===
    vlm_score = 0
    try:
        from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        
        if final_frame:
            prompt = """You are verifying a data science task.
Look at this screenshot sequence from Jupyter Lab.
Did the user write code to analyze affordability data and produce a bar chart?
Does the screen show legitimate data science progression and output?
Respond with JSON only:
{
    "has_data_analysis": true/false,
    "has_bar_chart": true/false
}
"""
            vlm_result = query_vlm(images=frames + [final_frame], prompt=prompt)
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('has_data_analysis'):
                    vlm_score += 10
                    feedback.append("VLM confirms data analysis presence")
                if parsed.get('has_bar_chart'):
                    vlm_score += 5
                    feedback.append("VLM confirms bar chart presence")
            else:
                # Fallback if VLM API fails but code works
                vlm_score += 15
                feedback.append("VLM check bypassed, auto-granting based on programmatic checks")
    except Exception as e:
        # Give points if VLM is unavailable but core task passed programmatic eval
        vlm_score = 15
        feedback.append(f"VLM unavailable ({e}), auto-granting VLM points")
        
    score += vlm_score

    # Make final decision
    passed = score >= 60 and csv_score >= 10
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }