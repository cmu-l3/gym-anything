#!/usr/bin/env python3
"""
Verifier for Multivariate Outlier Detection (Mahalanobis Distance) task.

Checks:
1. CSV output file exists and was created during the task.
2. Contains required columns: food_exp, income, m_dist, is_outlier.
3. 'm_dist' values match the mathematically correct squared Mahalanobis distances.
4. 'is_outlier' flags are correct based on the critical value 5.991.
"""

import json
import os
import tempfile
import logging
import pandas as pd
import numpy as np
from scipy.spatial.distance import mahalanobis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multivariate_outlier(traj, env_info, task_info):
    """
    Verify the Gretl script output for outlier detection.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('output_path', '/home/ga/Documents/gretl_output/food_with_outliers.csv')
    critical_val = metadata.get('critical_value', 5.991)

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_meta.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file was not created."}

    # 2. Retrieve Output CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(expected_path, temp_csv.name)
        # Try reading with different delimiters just in case (Gretl usually uses comma or tab)
        try:
            df = pd.read_csv(temp_csv.name)
            # If only 1 column detected, try tab or semicolon
            if len(df.columns) < 2:
                df = pd.read_csv(temp_csv.name, sep=None, engine='python')
        except Exception as e:
            return {"passed": False, "score": 20, "feedback": f"File created but could not be parsed as CSV: {str(e)}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve output CSV: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 3. Check Columns
    # Normalize column names to lowercase to be lenient
    df.columns = [c.lower().strip() for c in df.columns]
    required_cols = ['food_exp', 'income', 'm_dist', 'is_outlier']
    missing_cols = [c for c in required_cols if c not in df.columns]
    
    if missing_cols:
        return {
            "passed": False, 
            "score": 20, 
            "feedback": f"Output CSV missing required columns: {', '.join(missing_cols)}"
        }

    # 4. Verify Calculations
    score = 40  # Base score for having file + columns
    
    try:
        # Extract data for calculation
        data = df[['food_exp', 'income']].values.astype(float)
        
        # Calculate Ground Truth Mahalanobis Distances
        # D^2 = (x - mean)^T * Cov^-1 * (x - mean)
        # Note: Gretl uses sample covariance (N-1) by default usually, assume sample.
        cov_matrix = np.cov(data, rowvar=False)
        inv_cov = np.linalg.inv(cov_matrix)
        mean_dist = np.mean(data, axis=0)
        
        calculated_m_dist = []
        for i in range(data.shape[0]):
            p = data[i]
            d = mahalanobis(p, mean_dist, inv_cov)
            calculated_m_dist.append(d ** 2) # Task asks for squared distance
            
        calculated_m_dist = np.array(calculated_m_dist)
        
        # Compare m_dist
        agent_m_dist = df['m_dist'].values.astype(float)
        
        # Tolerance: 0.05 (allowing for slight differences in precision or N vs N-1 denominators)
        diff = np.abs(agent_m_dist - calculated_m_dist)
        valid_dist = np.all(diff < 0.05)
        
        if valid_dist:
            score += 40
        else:
            max_diff = np.max(diff)
            return {
                "passed": False, 
                "score": score, 
                "feedback": f"Mahalanobis distance values incorrect. Max difference: {max_diff:.4f}. Ensure you calculated squared distance using proper covariance."
            }

        # 5. Verify Logic (is_outlier)
        # Re-apply threshold logic
        expected_outlier = (calculated_m_dist > critical_val).astype(int)
        agent_outlier = df['is_outlier'].values.astype(int)
        
        if np.array_equal(expected_outlier, agent_outlier):
            score += 20
        else:
            mismatches = np.sum(expected_outlier != agent_outlier)
            return {
                "passed": False, 
                "score": score, 
                "feedback": f"Outlier flags incorrect. {mismatches} mismatches found against threshold {critical_val}."
            }

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error verifying calculations: {str(e)}"}

    return {
        "passed": True,
        "score": 100,
        "feedback": "Task completed successfully. Output file exists, format is correct, distances and outlier flags match ground truth."
    }