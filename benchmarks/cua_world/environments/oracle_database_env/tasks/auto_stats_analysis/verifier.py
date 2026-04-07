#!/usr/bin/env python3
"""
Verifier for auto_stats_analysis task.

Verifies:
1. `STATS_MODEL` view exists and contains correct regression statistics.
2. `EFFICIENT_OUTLIERS` table exists and correctly identifies vehicles performing better than the model.
3. Values (Slope, Intercept, Correlation, Prediction Diff) are within tolerance.

Ground truth is calculated dynamically from the raw data exported from the container to ensure robustness.
"""

import json
import logging
import math
import os
import tempfile
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_ground_truth(data_points):
    """
    Calculates linear regression stats from raw data points.
    data_points: list of dicts {'weight': x, 'mpg': y}
    """
    X = np.array([d['weight'] for d in data_points])
    Y = np.array([d['mpg'] for d in data_points])
    
    n = len(X)
    if n < 2:
        return None

    # Linear Regression (Least Squares)
    slope, intercept = np.polyfit(X, Y, 1)
    
    # Correlation Coefficient (Pearson)
    corr_matrix = np.corrcoef(X, Y)
    corr = corr_matrix[0, 1]
    
    # Standard Deviation of Y (MPG)
    std_dev = np.std(Y, ddof=1) # Sample standard deviation (Oracle STDDEV is sample by default usually, strictly STDDEV_SAMP)
    
    # Outliers Logic: Actual > Predicted + 1.5 * StdDev
    outliers = []
    for d in data_points:
        weight = d['weight']
        actual = d['mpg']
        predicted = slope * weight + intercept
        threshold = predicted + (1.5 * std_dev)
        
        if actual > threshold:
            outliers.append({
                'weight': weight,
                'actual': actual,
                'predicted': predicted,
                'diff': actual - predicted
            })
            
    return {
        'slope': slope,
        'intercept': intercept,
        'corr': corr,
        'std_dev': std_dev,
        'outliers': outliers
    }

def verify_auto_stats_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Recalculate Ground Truth
    raw_data = result.get('raw_data_points', [])
    if not raw_data:
        return {"passed": False, "score": 0, "feedback": "Could not retrieve raw data to verify statistics."}
    
    gt = calculate_ground_truth(raw_data)
    
    # --- Criterion 1: View Existence (10 pts) ---
    if result.get('stats_model_view_exists'):
        score += 10
        feedback.append("View STATS_MODEL created.")
    else:
        feedback.append("View STATS_MODEL not found.")
        
    # --- Criterion 2: Statistical Accuracy (45 pts total) ---
    agent_stats = result.get('stats_model_data', {})
    
    # Check Slope (15 pts)
    agent_slope = agent_stats.get('SLOPE')
    if agent_slope is not None and math.isclose(agent_slope, gt['slope'], abs_tol=0.0001):
        score += 15
        feedback.append(f"Slope correct ({agent_slope:.5f}).")
    else:
        feedback.append(f"Slope incorrect. Expected {gt['slope']:.5f}, got {agent_slope}.")

    # Check Intercept (15 pts)
    agent_int = agent_stats.get('INTERCEPT')
    # Use larger tolerance for intercept as it's a larger number usually
    if agent_int is not None and math.isclose(agent_int, gt['intercept'], rel_tol=0.01):
        score += 15
        feedback.append(f"Intercept correct ({agent_int:.2f}).")
    else:
        feedback.append(f"Intercept incorrect. Expected {gt['intercept']:.2f}, got {agent_int}.")

    # Check Correlation (15 pts)
    agent_corr = agent_stats.get('WEIGHT_MPG_CORR')
    if agent_corr is not None and math.isclose(agent_corr, gt['corr'], abs_tol=0.01):
        score += 15
        feedback.append(f"Correlation correct ({agent_corr:.4f}).")
    else:
        feedback.append(f"Correlation incorrect. Expected {gt['corr']:.4f}, got {agent_corr}.")

    # --- Criterion 3: Outlier Table Existence (10 pts) ---
    if result.get('efficient_outliers_table_exists'):
        score += 10
        feedback.append("Table EFFICIENT_OUTLIERS created.")
    else:
        feedback.append("Table EFFICIENT_OUTLIERS not found.")
        
    # --- Criterion 4: Outlier Logic & Content (35 pts total) ---
    agent_outliers = result.get('efficient_outliers_data', [])
    gt_outliers = gt['outliers']
    
    # Check if count matches
    if len(agent_outliers) == len(gt_outliers):
        score += 10
        feedback.append(f"Correct number of outliers found ({len(gt_outliers)}).")
    else:
        feedback.append(f"Incorrect number of outliers. Expected {len(gt_outliers)}, got {len(agent_outliers)}.")
        
    # Check if specific high-efficiency vehicles are present
    # We check if the weights in the agent's list match the weights in GT list (Weight is a good proxy for ID here)
    gt_weights = set([round(o['weight']) for o in gt_outliers])
    agent_weights = set([round(o.get('CURB_WEIGHT_LBS', 0)) for o in agent_outliers])
    
    intersection = gt_weights.intersection(agent_weights)
    if len(intersection) == len(gt_weights) and len(gt_weights) > 0:
        score += 10
        feedback.append("Correct vehicles identified as outliers.")
    else:
        feedback.append(f"Outlier vehicles mismatch. Found {len(intersection)}/{len(gt_weights)} expected.")
        
    # Check calculation columns (Predicted, Diff)
    # Check top 1 outlier details
    if agent_outliers and len(agent_outliers) > 0:
        top_agent = agent_outliers[0]
        # Find matching GT outlier
        match = next((o for o in gt_outliers if math.isclose(o['weight'], top_agent.get('CURB_WEIGHT_LBS', 0), abs_tol=1.0)), None)
        
        if match:
            pred_ok = math.isclose(top_agent.get('PREDICTED_MPG', 0), match['predicted'], abs_tol=1.0)
            diff_ok = math.isclose(top_agent.get('DIFF_FROM_MODEL', 0), match['diff'], abs_tol=1.0)
            
            if pred_ok and diff_ok:
                score += 15
                feedback.append("Calculated columns (Predicted, Diff) are accurate.")
            else:
                feedback.append("Calculated columns have errors.")
    
    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback)
    }