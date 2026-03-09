#!/usr/bin/env python3
import json
import os
import tempfile
import math
import numpy as np
import pandas as pd
from scipy import stats

def verify_distribution_analysis(traj, env_info, task_info):
    """
    Verifies the Distribution Analysis task.
    
    Criteria:
    1. OMV file exists and was created during the task.
    2. Report text file exists.
    3. Report values (15th %ile, 85th %ile, Skewness, SE Skewness) match ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    temp_dataset = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    
    score = 0
    feedback = []
    
    try:
        # 1. Load result JSON
        copy_from_env("/tmp/task_result.json", temp_result)
        with open(temp_result, 'r') as f:
            result = json.load(f)
            
        # 2. Check OMV File (20 points)
        if result.get('omv_exists') and result.get('omv_created_during_task'):
            score += 20
            feedback.append("Jamovi analysis file (.omv) created successfully.")
        elif result.get('omv_exists'):
            score += 10
            feedback.append("Jamovi analysis file exists but timestamp is old.")
        else:
            feedback.append("Jamovi analysis file not found.")

        # 3. Calculate Ground Truth
        # We need the dataset to calculate truth. Ideally we pull it from the container to match exactly.
        dataset_path = result.get('dataset_path', "/home/ga/Documents/Jamovi/ExamAnxiety.csv")
        try:
            copy_from_env(dataset_path, temp_dataset)
            df = pd.read_csv(temp_dataset)
            
            # Filter valid data (Revise variable)
            data = df['Revise'].dropna().astype(float)
            n = len(data)
            
            # Metrics
            # Percentiles: numpy uses linear interpolation by default (Type 7 in R/Jamovi)
            p15 = np.percentile(data, 15)
            p85 = np.percentile(data, 85)
            
            # Skewness: Fisher-Pearson coefficient of skewness (Jamovi default)
            # Pandas skew() computes unbiased skewness, which matches standard software
            skew = data.skew()
            
            # SE Skewness: Sqrt( 6n(n-1) / ((n-2)(n+1)(n+3)) )
            se_skew = math.sqrt((6 * n * (n - 1)) / ((n - 2) * (n + 1) * (n + 3)))
            
            ground_truth = {
                "p15": p15,
                "p85": p85,
                "skew": skew,
                "se_skew": se_skew
            }
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to calculate ground truth from dataset: {str(e)}"}

        # 4. Verify Report Content (80 points total)
        if result.get('report_exists'):
            score += 10 # File exists
            
            try:
                copy_from_env(result.get('report_path'), temp_report)
                with open(temp_report, 'r') as f:
                    lines = [l.strip() for l in f.readlines() if l.strip()]
                
                if len(lines) >= 4:
                    try:
                        val_p15 = float(lines[0])
                        val_p85 = float(lines[1])
                        val_skew = float(lines[2])
                        val_se = float(lines[3])
                        
                        # Tolerances
                        tol = 0.05
                        
                        # Check 15th Percentile (20 pts)
                        if abs(val_p15 - ground_truth['p15']) <= 0.5: # Slightly higher tolerance for percentiles due to interp method variances
                            score += 20
                            feedback.append(f"15th Percentile correct ({val_p15}).")
                        else:
                            feedback.append(f"15th Percentile incorrect (Expected {ground_truth['p15']:.2f}, got {val_p15}).")

                        # Check 85th Percentile (20 pts)
                        if abs(val_p85 - ground_truth['p85']) <= 0.5:
                            score += 20
                            feedback.append(f"85th Percentile correct ({val_p85}).")
                        else:
                            feedback.append(f"85th Percentile incorrect (Expected {ground_truth['p85']:.2f}, got {val_p85}).")

                        # Check Skewness (15 pts)
                        if abs(val_skew - ground_truth['skew']) <= tol:
                            score += 15
                            feedback.append(f"Skewness correct ({val_skew}).")
                        else:
                            feedback.append(f"Skewness incorrect (Expected {ground_truth['skew']:.2f}, got {val_skew}).")
                            
                        # Check SE Skewness (15 pts)
                        if abs(val_se - ground_truth['se_skew']) <= tol:
                            score += 15
                            feedback.append(f"SE Skewness correct ({val_se}).")
                        else:
                            feedback.append(f"SE Skewness incorrect (Expected {ground_truth['se_skew']:.2f}, got {val_se}).")

                    except ValueError:
                        feedback.append("Report format error: Could not parse numbers.")
                else:
                    feedback.append("Report incomplete: Expected 4 lines.")
            except Exception as e:
                feedback.append(f"Error reading report: {str(e)}")
        else:
            feedback.append("Report file not found.")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification system error: {str(e)}"}
    finally:
        # Cleanup
        for f in [temp_result, temp_report, temp_dataset]:
            if os.path.exists(f):
                os.remove(f)

    # Final pass logic
    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }