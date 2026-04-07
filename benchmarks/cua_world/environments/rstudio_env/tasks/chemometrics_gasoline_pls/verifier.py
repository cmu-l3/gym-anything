#!/usr/bin/env python3
"""
Verifier for chemometrics_gasoline_pls task.

Scoring (100 points total):
1. Install & Setup (15 pts): 'pls' package installed, script modified.
2. Modeling (20 pts): CV Performance CSV exists and contains valid RMSEP data.
3. Prediction Accuracy (35 pts): Predictions CSV exists, matches format, and RMSE < 0.5.
4. Visualization (30 pts): Loadings plot (15) and Scatter plot (15) exist.

Pass Threshold: 60 points.
"""

import json
import tempfile
import os
import csv
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth for the last 10 samples of pls::gasoline$octane
# Indices 51 to 60
GROUND_TRUTH_OCTANE = [88.45, 87.20, 86.60, 87.10, 87.90, 85.30, 85.20, 88.70, 86.30, 84.40]

def verify_chemometrics_pls(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # 1. Install & Setup (15 pts)
    if result.get('pls_installed', False):
        score += 10
        feedback.append("Package 'pls' successfully installed (+10)")
    else:
        feedback.append("Package 'pls' NOT installed (0)")
    
    if result.get('script_modified', False):
        score += 5
        feedback.append("Analysis script created/modified (+5)")
    else:
        feedback.append("Analysis script not modified (0)")

    # 2. Modeling (20 pts) - Check CV CSV
    cv_exists = result.get('cv_exists', False)
    if cv_exists:
        # Verify content
        temp_cv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/tmp/cv_data.csv", temp_cv.name)
            with open(temp_cv.name, 'r') as f:
                reader = csv.reader(f)
                rows = list(reader)
                if len(rows) > 1: # Header + data
                    score += 20
                    feedback.append("CV performance table valid (+20)")
                else:
                    score += 5
                    feedback.append("CV table empty or invalid (+5)")
        except Exception:
            feedback.append("CV table exists but unreadable (0)")
        finally:
            if os.path.exists(temp_cv.name):
                os.unlink(temp_cv.name)
    else:
        feedback.append("CV performance table missing (0)")

    # 3. Prediction Accuracy (35 pts)
    pred_exists = result.get('pred_exists', False)
    if pred_exists:
        temp_pred = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/tmp/pred_data.csv", temp_pred.name)
            
            # Read predictions
            preds = []
            actuals = []
            with open(temp_pred.name, 'r') as f:
                reader = csv.DictReader(f)
                # Normalize headers
                headers = [h.lower() for h in reader.fieldnames] if reader.fieldnames else []
                
                # Try to map columns
                pred_col = next((h for h in reader.fieldnames if 'pred' in h.lower()), None)
                act_col = next((h for h in reader.fieldnames if 'act' in h.lower() or 'meas' in h.lower()), None)

                if pred_col:
                    for row in reader:
                        try:
                            p = float(row[pred_col])
                            preds.append(p)
                            # If they included actuals, verify them against ground truth roughly
                            if act_col:
                                actuals.append(float(row[act_col]))
                        except ValueError:
                            continue
            
            if len(preds) != 10:
                feedback.append(f"Prediction file has {len(preds)} rows, expected 10.")
                # Penalty but continue if possible
            
            # Calculate RMSE against GROUND TRUTH (ignore their actual column for scoring to prevent lying)
            if len(preds) == 10:
                squared_errors = [(p - a) ** 2 for p, a in zip(preds, GROUND_TRUTH_OCTANE)]
                rmse = math.sqrt(sum(squared_errors) / len(squared_errors))
                
                feedback.append(f"Test RMSE: {rmse:.4f}")
                
                if rmse < 0.5:
                    score += 35
                    feedback.append("RMSE < 0.5 (Excellent) (+35)")
                elif rmse < 1.0:
                    score += 20
                    feedback.append("RMSE < 1.0 (Acceptable) (+20)")
                else:
                    score += 5
                    feedback.append("RMSE >= 1.0 (Poor model or wrong component count) (+5)")
            else:
                feedback.append("Incorrect number of predictions (0)")

        except Exception as e:
            feedback.append(f"Error reading predictions: {e}")
        finally:
            if os.path.exists(temp_pred.name):
                os.unlink(temp_pred.name)
    else:
        feedback.append("Predictions CSV missing (0)")

    # 4. Visualization (30 pts)
    if result.get('loadings_exists', False):
        score += 15
        feedback.append("Loadings plot created (+15)")
    else:
        feedback.append("Loadings plot missing (0)")
        
    if result.get('scatter_exists', False):
        score += 15
        feedback.append("Predicted vs Measured plot created (+15)")
    else:
        feedback.append("Scatter plot missing (0)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }