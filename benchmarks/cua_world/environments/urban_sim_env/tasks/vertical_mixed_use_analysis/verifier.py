#!/usr/bin/env python3
"""
Verifier for Vertical Mixed-Use Analysis task.
Validates programmatic notebook execution, structural artifact requirements,
and strict data accuracy via ground truth calculated safely within the environment.
"""

import json
import tempfile
import os

def verify_vertical_mixed_use_analysis(traj, env_info, task_info):
    """
    Scoring Breakdown (100 points):
    1. Notebook Exists & Executed (10 pts)
    2. CSV Structure (10 pts)
    3. Correct Zone Filtering (15 pts)
    4. Data Join Accuracy (CSV metrics match ground truth) (30 pts)
    5. JSON Summary Correctness (25 pts)
    6. Visualization Exists (10 pts)

    Pass condition: Total score >= 75 AND Data Join Accuracy demonstrated (csv_sample_match == True).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_cols = metadata.get('expected_csv_columns', ["total_buildings", "vmu_buildings", "pct_vmu", "vmu_households", "vmu_jobs"])
    expected_json_keys = metadata.get('expected_json_keys', ["total_analyzed_zones", "citywide_vmu_buildings", "citywide_pct_vmu", "top_vmu_zone_id"])
    
    score = 0
    feedback = []

    # Read result populated by the export script
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read task result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    if result.get("ground_truth_error"):
        feedback.append(f"Environment Error processing Ground Truth: {result.get('ground_truth_error')}")
    
    gt = result.get('ground_truth', {})

    # 1. Notebook Evaluation (10 pts)
    nb_score = 0
    if result.get('notebook_exists'):
        nb_score += 4
        nb_analysis = result.get('notebook_analysis', {})
        if nb_analysis.get('has_code') and result.get('notebook_modified'):
            nb_score += 3
        if nb_analysis.get('num_executed_cells', 0) >= 3:
            nb_score += 3
    score += nb_score
    feedback.append(f"Notebook: {nb_score}/10")

    # 2. CSV Structure (10 pts)
    csv_structure_score = 0
    if result.get('csv_exists'):
        csv_structure_score += 5
        agent_cols = result.get('csv_columns', [])
        found_expected_cols = sum(1 for req_col in expected_csv_cols if any(req_col in c for c in agent_cols))
        if found_expected_cols == len(expected_csv_cols):
            csv_structure_score += 5
        elif found_expected_cols > 0:
            csv_structure_score += int(5 * (found_expected_cols / len(expected_csv_cols)))
    score += csv_structure_score
    feedback.append(f"CSV Structure: {csv_structure_score}/10")

    # 3. Correct Zone Filtering (15 pts)
    filtering_score = 0
    if result.get('csv_exists') and 'total_analyzed_zones' in gt:
        expected_rows = gt['total_analyzed_zones']
        agent_rows = result.get('csv_rows', 0)
        
        if expected_rows > 0:
            # Allow minor deviation due to possible index handling or header parsing
            diff = abs(expected_rows - agent_rows)
            if diff == 0:
                filtering_score += 15
            elif diff <= 2:
                filtering_score += 10
            elif abs(diff) < expected_rows * 0.1: # 10% tolerance
                filtering_score += 5
    score += filtering_score
    feedback.append(f"Zone Filtering: {filtering_score}/15")

    # 4. Data Join Accuracy (30 pts)
    join_score = 0
    csv_sample_match = result.get('csv_sample_match', False)
    if csv_sample_match:
        join_score = 30
    elif result.get("csv_match_details", {}).get("matched", 0) > 0:
        matched = result.get("csv_match_details", {}).get("matched", 0)
        checked = max(1, result.get("csv_match_details", {}).get("checked", 1))
        join_score = int(30 * (matched / checked))
    score += join_score
    feedback.append(f"Data Join Accuracy: {join_score}/30")

    # 5. JSON Summary Correctness (25 pts)
    json_score = 0
    if result.get('json_exists'):
        agent_json = result.get('agent_json', {})
        keys_present = sum(1 for k in expected_json_keys if k in agent_json)
        if keys_present == len(expected_json_keys):
            json_score += 5
            
            # Check metric accuracy against ground truth mathematically
            try:
                # 1. Total Zones Match (5 pts)
                if abs(float(agent_json.get('total_analyzed_zones', -1)) - float(gt.get('total_analyzed_zones', 0))) <= 1:
                    json_score += 5
                
                # 2. Total VMU buildings (5 pts)
                if abs(float(agent_json.get('citywide_vmu_buildings', -1)) - float(gt.get('citywide_vmu_buildings', 0))) <= 1:
                    json_score += 5
                
                # 3. Pct VMU match (5 pts - allow 0.01 tolerance)
                if abs(float(agent_json.get('citywide_pct_vmu', -1)) - float(gt.get('citywide_pct_vmu', 0))) <= 0.01:
                    json_score += 5
                
                # 4. Top zone match (5 pts)
                if str(agent_json.get('top_vmu_zone_id', -1)).strip() == str(gt.get('top_vmu_zone_id', 0)).strip():
                    json_score += 5
            except (ValueError, TypeError):
                pass
    score += json_score
    feedback.append(f"JSON Accuracy: {json_score}/25")

    # 6. Visualization Exists (10 pts)
    plot_score = 0
    if result.get('plot_exists'):
        plot_score += 5
        if result.get('plot_created'):
            plot_score += 2
        if result.get('plot_size_kb', 0) >= 5:
            plot_score += 3
    score += plot_score
    feedback.append(f"Plot Artifact: {plot_score}/10")

    passed = score >= 75 and csv_sample_match
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }