#!/usr/bin/env python3
"""
Verifier for loglinear_titanic_survival task.

Verification Strategy:
1. Computational Ground Truth:
   - Reads the raw 'TitanicSurvival.csv' data (copied from env).
   - Computes the Log-Linear model (Poisson regression on contingency table).
   - Calculates Deviance (G^2), DF, and p-value for the model [survived, sex, class, interactions(2-way)].
2. Report Verification:
   - Reads the agent's 'loglinear_report.txt'.
   - Compares reported values against computed ground truth.
3. Artifact Verification:
   - Checks if .omv file was created and is valid.

Points:
- OMV file exists/valid: 20 pts
- Report file exists: 10 pts
- Deviance Correct (+/- 0.5): 20 pts
- DF Correct (Exact): 15 pts
- P-value Correct (+/- 0.01): 15 pts
- Conclusion Correct (Adequate/Inadequate): 20 pts
"""

import json
import os
import tempfile
import logging
import pandas as pd
import numpy as np
import scipy.stats as stats
import statsmodels.api as sm
import statsmodels.formula.api as smf

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_loglinear_titanic_survival(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # Files to copy
    result_json_path = "/tmp/task_result.json"
    report_path = task_info.get("metadata", {}).get("report_output_path", "/home/ga/Documents/Jamovi/loglinear_report.txt")
    dataset_path = task_info.get("metadata", {}).get("dataset_path", "/home/ga/Documents/Jamovi/TitanicSurvival.csv")
    
    # Temporary files on host
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    temp_data = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name

    try:
        # 1. Load Task Result JSON
        try:
            copy_from_env(result_json_path, temp_result)
            with open(temp_result, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # 2. Check OMV File (20 pts)
        if task_result.get("omv_exists") and task_result.get("omv_created_during_task") and task_result.get("omv_size_bytes", 0) > 1000:
            score += 20
            feedback.append("Jamovi project file (.omv) created successfully.")
        else:
            feedback.append("Jamovi project file missing, too small, or not new.")

        # 3. Compute Ground Truth
        try:
            copy_from_env(dataset_path, temp_data)
            df = pd.read_csv(temp_data)
            
            # Prepare data: Contingency Table -> Long Format for Poisson Regression
            # Variables: survived, sex, passengerClass
            # Drop NAs
            df_clean = df.dropna(subset=['survived', 'sex', 'passengerClass'])
            
            # Create contingency table (counts)
            counts = df_clean.groupby(['survived', 'sex', 'passengerClass']).size().reset_index(name='Freq')
            
            # Fit Log-Linear Model (Poisson Regression)
            # Saturated Model (for deviance ref): Freq ~ survived*sex*passengerClass
            # Target Model (All 2-way): Freq ~ survived*sex + survived*passengerClass + sex*passengerClass
            # Note: Main effects are automatically included when interactions are specified in formula
            
            # We calculate Deviance as the difference in Deviance between our model and the saturated model.
            # However, statsmodels Poisson 'deviance' attribute IS the deviance relative to saturated model.
            
            model_formula = "Freq ~ survived*sex + survived*passengerClass + sex*passengerClass"
            model = smf.glm(formula=model_formula, data=counts, family=sm.families.Poisson()).fit()
            
            gt_deviance = model.deviance
            gt_df = model.df_resid # Degrees of freedom of residuals (for deviance test)
            gt_p_value = 1 - stats.chi2.cdf(gt_deviance, gt_df)
            gt_conclusion = "ADEQUATE" if gt_p_value > 0.05 else "INADEQUATE"
            
            # Double check DF logic:
            # 2x2x3 table = 12 cells.
            # Saturated params = 12.
            # Model params:
            # Intercept (1)
            # Survived (1)
            # Sex (1)
            # Class (2)
            # Surv*Sex (1)
            # Surv*Class (2)
            # Sex*Class (2)
            # Total params = 1+1+1+2+1+2+2 = 10.
            # DF = 12 - 10 = 2.
            # Matches theoretical DF: (I-1)(J-1)(K-1) = 1*1*2 = 2.
            
            logger.info(f"Ground Truth: Deviance={gt_deviance:.4f}, DF={gt_df}, p={gt_p_value:.4f}")
            
        except Exception as e:
            logger.error(f"Ground truth calculation failed: {e}")
            return {"passed": False, "score": score, "feedback": f"Verifier failed to compute ground truth: {e}"}

        # 4. Check Report Content
        if task_result.get("report_exists"):
            score += 10
            feedback.append("Report file exists.")
            
            try:
                copy_from_env(report_path, temp_report)
                with open(temp_report, 'r') as f:
                    lines = [l.strip() for l in f.readlines() if l.strip()]
                
                if len(lines) >= 4:
                    # Parse agent values
                    try:
                        agent_deviance = float(lines[0])
                        agent_df = int(float(lines[1])) # Handle "2.0"
                        agent_p = float(lines[2])
                        agent_conc = lines[3].upper()
                        
                        # Verify Deviance (20 pts)
                        if abs(agent_deviance - gt_deviance) <= 0.5:
                            score += 20
                            feedback.append(f"Deviance correct (Agent: {agent_deviance}, GT: {gt_deviance:.2f}).")
                        else:
                            feedback.append(f"Deviance incorrect (Agent: {agent_deviance}, Expected: {gt_deviance:.2f}).")
                            
                        # Verify DF (15 pts)
                        if agent_df == int(gt_df):
                            score += 15
                            feedback.append(f"Degrees of Freedom correct ({agent_df}).")
                        else:
                            feedback.append(f"Degrees of Freedom incorrect (Agent: {agent_df}, Expected: {int(gt_df)}).")
                            
                        # Verify P-value (15 pts)
                        if abs(agent_p - gt_p_value) <= 0.01:
                            score += 15
                            feedback.append(f"P-value correct (Agent: {agent_p}, GT: {gt_p_value:.4f}).")
                        else:
                            feedback.append(f"P-value incorrect (Agent: {agent_p}, Expected: {gt_p_value:.4f}).")
                            
                        # Verify Conclusion (20 pts)
                        if agent_conc == gt_conclusion:
                            score += 20
                            feedback.append(f"Conclusion correct ({agent_conc}).")
                        else:
                            feedback.append(f"Conclusion incorrect (Agent: {agent_conc}, Expected: {gt_conclusion}).")
                            
                    except ValueError:
                        feedback.append("Could not parse numbers from report. Ensure format is exactly 4 lines as requested.")
                else:
                    feedback.append(f"Report has insufficient lines ({len(lines)}/4).")
                    
            except Exception as e:
                feedback.append(f"Failed to read report content: {e}")
        else:
            feedback.append("Report file not found.")

        # Final check
        passed = score >= 80  # Strict pass threshold due to specific numeric requirements
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
        
    finally:
        # Cleanup
        for f in [temp_result, temp_report, temp_data]:
            if os.path.exists(f):
                os.unlink(f)