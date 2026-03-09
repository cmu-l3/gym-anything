#!/usr/bin/env python3
"""
Verifier for Classify Channel Shape task.
"""

import json
import pandas as pd
import numpy as np
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_classify_channel_shape(traj, env_info, task_info):
    """
    Verify the channel shape analysis.
    
    Criteria:
    1. Simulation ran (HDF5 modified). (10 pts)
    2. Output CSV exists and has correct columns. (10 pts)
    3. Peak WSE matches simulation results (tolerance 0.05 ft). (15 pts)
    4. Max Depth matches (WSE - MinElev) (tolerance 0.1 ft). (15 pts)
    5. Hydraulic Depth calculation is mathematically consistent (D = A/T). (10 pts)
    6. Shape Factor calculation is consistent (SF = D/Y). (10 pts)
    7. Classification logic is correct based on SF thresholds. (20 pts)
    8. Script usage/VLM (10 pts).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Load Task Result JSON
    try:
        temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            task_result = json.load(f)
        os.unlink(temp_res.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    # Check Simulation
    if task_result.get("simulation_ran"):
        score += 10
        feedback.append("Simulation executed successfully.")
    else:
        feedback.append("Simulation results file was not updated.")

    # Check CSV Existence
    if not task_result.get("csv_exists"):
        return {"passed": False, "score": score, "feedback": "Output CSV not found."}
    
    score += 10
    feedback.append("Output CSV found.")

    # 2. Load Agent CSV and Ground Truth CSV
    try:
        # Load Agent CSV
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        copy_from_env(task_result["csv_path"], temp_csv.name)
        agent_df = pd.read_csv(temp_csv.name)
        os.unlink(temp_csv.name)
        
        # Load Ground Truth CSV (contains WSE and MinElev reference)
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        copy_from_env(task_result["ground_truth_path"], temp_gt.name)
        gt_df = pd.read_csv(temp_gt.name)
        os.unlink(temp_gt.name)
        
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read CSV files: {e}"}

    # 3. Validation
    
    # Check Columns
    req_cols = ["River_Station", "Peak_WSE", "Flow_Area", "Top_Width", "Hydraulic_Depth", "Max_Depth", "Shape_Factor", "Classification"]
    if not all(col in agent_df.columns for col in req_cols):
        feedback.append(f"Missing required columns. Found: {list(agent_df.columns)}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Clean data types
    numeric_cols = ["Peak_WSE", "Flow_Area", "Top_Width", "Hydraulic_Depth", "Max_Depth", "Shape_Factor"]
    for col in numeric_cols:
        agent_df[col] = pd.to_numeric(agent_df[col], errors='coerce')

    # Merge with Ground Truth on River_Station
    # Ensure River_Station is string
    agent_df['River_Station'] = agent_df['River_Station'].astype(str).str.strip()
    gt_df['River_Station'] = gt_df['River_Station'].astype(str).str.strip()
    
    merged = pd.merge(agent_df, gt_df, on="River_Station", how="inner", suffixes=("_agent", "_gt"))
    
    if len(merged) == 0:
        feedback.append("No matching river stations found between agent output and ground truth.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Metric 1: Peak WSE Accuracy (15 pts)
    # Allow 0.05 ft tolerance
    wse_diff = np.abs(merged["Peak_WSE_agent"] - merged["Peak_WSE_gt"])
    valid_wse = wse_diff < 0.05
    wse_score = (valid_wse.sum() / len(merged)) * 15
    score += wse_score
    if wse_score < 10:
        feedback.append(f"WSE accuracy low. Mean diff: {wse_diff.mean():.4f}")
    else:
        feedback.append("Peak WSE values match simulation.")

    # Metric 2: Max Depth Accuracy (15 pts)
    # Max Depth = WSE - Min_Elev
    # We check if Agent's MaxDepth ~= Agent's WSE - GT's Min_Elev
    # This confirms they found the thalweg correctly
    calc_depth = merged["Peak_WSE_agent"] - merged["Min_Elev"]
    depth_diff = np.abs(merged["Max_Depth"] - calc_depth)
    valid_depth = depth_diff < 0.1
    depth_score = (valid_depth.sum() / len(merged)) * 15
    score += depth_score
    
    # Metric 3: Internal Math Consistency (Hydraulic Depth) (10 pts)
    # D = A / T
    # Check if A / T approx D
    calc_D = merged["Flow_Area"] / merged["Top_Width"]
    # Handle div by zero
    calc_D = calc_D.fillna(0)
    math_diff = np.abs(merged["Hydraulic_Depth"] - calc_D)
    valid_math = math_diff < 0.01
    math_score = (valid_math.sum() / len(merged)) * 10
    score += math_score

    # Metric 4: Internal Math Consistency (Shape Factor) (10 pts)
    # SF = D / Ymax
    calc_SF = merged["Hydraulic_Depth"] / merged["Max_Depth"]
    calc_SF = calc_SF.fillna(0)
    sf_diff = np.abs(merged["Shape_Factor"] - calc_SF)
    valid_sf = sf_diff < 0.01
    sf_score = (valid_sf.sum() / len(merged)) * 10
    score += sf_score

    # Metric 5: Classification Logic (20 pts)
    # Re-classify based on Agent's own SF to test logic implementation
    def classify(sf):
        if sf < 0.65: return "Triangular"
        if sf <= 0.85: return "Parabolic"
        return "Rectangular"
    
    ref_class = merged["Shape_Factor"].apply(classify)
    # Case insensitive comparison
    class_match = merged["Classification"].str.lower() == ref_class.str.lower()
    class_score = (class_match.sum() / len(merged)) * 20
    score += class_score
    
    if class_score < 15:
        feedback.append("Classification logic seems incorrect based on thresholds.")
    
    # VLM/Script check (10 pts placeholder for basic check)
    # If they generated a CSV with >0 rows and >0 columns, they likely used a script
    if len(agent_df) > 5:
        score += 10
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": " | ".join(feedback)
    }