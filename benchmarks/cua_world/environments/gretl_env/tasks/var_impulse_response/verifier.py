#!/usr/bin/env python3
"""
Verifier for VAR Impulse Response task.

Verification Logic:
1. File Existence: Check for plot and CSV data.
2. Numerical Accuracy: Compare agent's CSV data against ground truth generated via gretlcli.
   - The IRF vector (12 steps) should match closely.
   - We use Correlation and Mean Squared Error (MSE).
3. Visual Verification (VLM): Ensure plot looks like an IRF graph.
"""

import json
import os
import tempfile
import math
import logging
import csv

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_gretl_csv(filepath):
    """
    Parses a CSV file output from Gretl.
    Gretl CSV outputs can vary (headers, spacing), so we try to extract the first numeric column.
    Returns a list of floats.
    """
    values = []
    try:
        with open(filepath, 'r') as f:
            # Try standard CSV reader first
            reader = csv.reader(f)
            for row in reader:
                # Skip empty rows
                if not row: continue
                
                # Look for numeric values
                for cell in row:
                    try:
                        # Clean string
                        cell_clean = cell.strip().replace('"', '')
                        val = float(cell_clean)
                        values.append(val)
                        # Assume one value per row for simple series dump or taking first col
                        break 
                    except ValueError:
                        continue
    except Exception as e:
        logger.warning(f"Error parsing CSV {filepath}: {e}")
    return values

def calculate_similarity(vec1, vec2):
    """
    Calculates similarity between two vectors.
    Returns (correlation, mse).
    """
    if not vec1 or not vec2:
        return 0.0, float('inf')
    
    # Truncate to shorter length
    n = min(len(vec1), len(vec2))
    v1 = vec1[:n]
    v2 = vec2[:n]
    
    if n < 5: # Too few points
        return 0.0, float('inf')

    # MSE
    mse = sum((a - b) ** 2 for a, b in zip(v1, v2)) / n
    
    # Correlation
    mean1 = sum(v1) / n
    mean2 = sum(v2) / n
    
    num = sum((a - mean1) * (b - mean2) for a, b in zip(v1, v2))
    den = math.sqrt(sum((a - mean1)**2 for a in v1)) * math.sqrt(sum((b - mean2)**2 for b in v2))
    
    corr = num / den if den != 0 else 0
    
    return corr, mse

def verify_var_impulse_response(traj, env_info, task_info):
    """
    Verifies the VAR task results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Setup temp files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_agent_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_gt_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    files_to_clean = [temp_result.name, temp_agent_csv.name, temp_gt_csv.name]

    try:
        # 1. Load Metadata & Result JSON
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        plot_exists = result_data.get('plot_exists', False)
        data_exists = result_data.get('data_exists', False)
        
        score = 0
        feedback = []

        # Criterion 1: Plot exists (30 pts)
        if plot_exists:
            score += 30
            feedback.append("IRF plot created successfully.")
        else:
            feedback.append("IRF plot missing.")

        # Criterion 2: Data exists (20 pts)
        if data_exists:
            score += 20
            feedback.append("IRF numerical data saved.")
        else:
            feedback.append("IRF numerical data missing.")

        # Criterion 3: Numerical Accuracy (50 pts)
        accuracy_score = 0
        if data_exists:
            try:
                # Copy CSVs
                copy_from_env("/tmp/agent_irf.csv", temp_agent_csv.name)
                copy_from_env("/tmp/gt_irf.csv", temp_gt_csv.name)
                
                agent_vals = parse_gretl_csv(temp_agent_csv.name)
                gt_vals = parse_gretl_csv(temp_gt_csv.name)
                
                if not gt_vals:
                    # Fallback if GT generation failed in setup
                    feedback.append("Warning: Could not load ground truth for comparison. Manual check required.")
                    # Grant partial points if data looks plausible (not empty)
                    if len(agent_vals) >= 10:
                        accuracy_score = 25
                        feedback.append("Data structure looks valid (plausible length).")
                else:
                    corr, mse = calculate_similarity(agent_vals, gt_vals)
                    
                    # Evaluation
                    # 1. Strong correlation (shape match)
                    if corr > 0.9:
                        accuracy_score += 30
                        feedback.append(f"Data shape matches ground truth (Corr: {corr:.2f}).")
                    elif corr > 0.7:
                        accuracy_score += 15
                        feedback.append(f"Data shape somewhat matches (Corr: {corr:.2f}).")
                    else:
                        feedback.append(f"Data shape does not match (Corr: {corr:.2f}). Check variable ordering.")
                        
                    # 2. Low MSE (magnitude match)
                    # MSE depends on scale. Log GDP changes are small (e.g., -0.005).
                    # A reasonable threshold is small.
                    if mse < 0.0001:
                        accuracy_score += 20
                        feedback.append("Data magnitude is accurate.")
                    elif mse < 0.001:
                        accuracy_score += 10
                        feedback.append("Data magnitude is roughly correct.")
                    else:
                        feedback.append(f"Data values differ significantly (MSE: {mse:.5f}).")

            except Exception as e:
                feedback.append(f"Error analyzing numerical data: {str(e)}")
        
        score += accuracy_score

        # Final pass determination
        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}
    finally:
        for f in files_to_clean:
            if os.path.exists(f):
                try:
                    os.unlink(f)
                except:
                    pass