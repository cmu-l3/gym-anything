#!/usr/bin/env python3
"""
Verifier for verify_levee_freeboard_compliance task.
"""

import json
import os
import pandas as pd
import numpy as np
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_levee_freeboard_compliance(traj, env_info, task_info):
    """
    Verifies the levee compliance report.
    Checks:
    1. CSV output existence and format.
    2. Calculation accuracy (WSE interpolation, Freeboard).
    3. Classification accuracy (PASS/FAIL).
    4. Plot existence.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_json.name)

    score = 0
    feedback = []

    # 1. Artifact Check (20 pts)
    if result.get('csv_exists'):
        score += 10
        feedback.append("Output CSV found.")
    else:
        feedback.append("Output CSV missing.")
    
    if result.get('plot_exists'):
        score += 10
        feedback.append("Output plot found.")
    else:
        feedback.append("Output plot missing.")

    # 2. Data Validation (80 pts)
    csv_valid = False
    
    # Copy CSVs from env
    agent_csv_path = result.get('agent_csv_path')
    gt_csv_path = result.get('ground_truth_path')
    
    if agent_csv_path and gt_csv_path:
        local_agent_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
        local_gt_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
        
        try:
            copy_from_env(agent_csv_path, local_agent_csv)
            copy_from_env(gt_csv_path, local_gt_csv)
            
            df_agent = pd.read_csv(local_agent_csv)
            df_gt = pd.read_csv(local_gt_csv)
            
            # Check Columns
            required_cols = ['Station_ft', 'Levee_Top_Elev_ft', 'Modeled_WSE_ft', 'Freeboard_ft', 'Status']
            missing_cols = [c for c in required_cols if c not in df_agent.columns]
            
            if not missing_cols:
                score += 10
                feedback.append("CSV columns correct.")
                
                # Align data by Station
                # Ensure we are comparing the same stations
                df_merged = pd.merge(df_gt, df_agent, on='Station_ft', suffixes=('_gt', '_agent'), how='inner')
                
                if len(df_merged) < len(df_gt) * 0.9:
                    feedback.append(f"Row count mismatch. Expected {len(df_gt)}, matched {len(df_merged)}.")
                else:
                    # Check WSE Interpolation (30 pts)
                    # Allow 0.1 ft tolerance
                    wse_diff = np.abs(df_merged['Modeled_WSE_ft_gt'] - df_merged['Modeled_WSE_ft_agent'])
                    mae_wse = wse_diff.mean()
                    if mae_wse < 0.1:
                        score += 30
                        feedback.append(f"Interpolation accuracy good (MAE: {mae_wse:.3f}).")
                    elif mae_wse < 0.5:
                        score += 15
                        feedback.append(f"Interpolation accuracy fair (MAE: {mae_wse:.3f}).")
                    else:
                        feedback.append(f"Interpolation poor (MAE: {mae_wse:.3f}). Check coordinate alignment.")
                    
                    # Check Freeboard Logic (20 pts)
                    # Freeboard = Levee - WSE
                    # Calc agent's implied freeboard
                    calc_fb = df_merged['Levee_Top_Elev_ft_agent'] - df_merged['Modeled_WSE_ft_agent']
                    fb_diff = np.abs(calc_fb - df_merged['Freeboard_ft_agent'])
                    if fb_diff.mean() < 0.05:
                        score += 20
                        feedback.append("Freeboard calculation logic correct.")
                    else:
                        feedback.append("Freeboard calculation logic inconsistent with columns.")

                    # Check Status Classification (20 pts)
                    # Should match ground truth exactly
                    status_match = (df_merged['Status_gt'] == df_merged['Status_agent']).mean()
                    if status_match > 0.95:
                        score += 20
                        feedback.append("Pass/Fail classification correct.")
                    else:
                        feedback.append(f"Classification mismatch ({status_match*100:.1f}% match).")
                        
            else:
                feedback.append(f"Missing columns: {missing_cols}")
                
        except Exception as e:
            feedback.append(f"Error validating data: {str(e)}")
            logger.exception("Validation error")
        finally:
            if os.path.exists(local_agent_csv): os.unlink(local_agent_csv)
            if os.path.exists(local_gt_csv): os.unlink(local_gt_csv)
    
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }