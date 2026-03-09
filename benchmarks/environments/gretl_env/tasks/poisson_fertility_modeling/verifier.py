#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import csv
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_poisson_fertility_modeling(traj, env_info, task_info):
    """
    Verifies the Poisson regression task.
    
    Criteria:
    1. Output files exist (results, fitted values, dispersion test).
    2. Results file confirms Poisson model on correct variables.
    3. Coefficients match expected signs/values.
    4. Fitted values are numeric and have correct mean (approx 0.237).
    5. Dispersion test file contains test output.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback = []
    
    # 1. Retrieve metadata and result JSON
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
            copy_from_env("/tmp/task_result.json", f.name)
            with open(f.name) as jf:
                result_data = json.load(jf)
        os.unlink(f.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

    files_info = result_data.get("files", {})
    
    # =========================================================
    # Check 1: Model Output File (30 points)
    # =========================================================
    results_info = files_info.get("results", {})
    if results_info.get("exists") and results_info.get("size", 0) > 50:
        score += 5
        feedback.append("Model output file exists.")
        
        # Analyze content
        try:
            with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f:
                copy_from_env("/tmp/poisson_results.txt", f.name)
                with open(f.name, 'r', encoding='utf-8', errors='ignore') as rf:
                    content = rf.read()
            os.unlink(f.name)
            
            # Check for Poisson
            if "Poisson" in content:
                score += 10
                feedback.append("Confirmed Poisson model used.")
            else:
                feedback.append("Model output does not mention 'Poisson'.")

            # Check for Dependent Variable
            if "kidslt6" in content:
                score += 5
                feedback.append("Dependent variable 'kidslt6' found.")
            
            # Check for Regressors
            regressors = ["const", "educ", "age", "exper", "nwifeinc"]
            found_regs = [r for r in regressors if r in content]
            if len(found_regs) == 5:
                score += 5
                feedback.append("All regressors present.")
            else:
                feedback.append(f"Missing regressors: {set(regressors) - set(found_regs)}")
                
            # Check Coefficient Sign for Education (should be negative)
            # Regex to find line like: "educ        -0.053..."
            educ_match = re.search(r"educ\s+([-\d\.]+)", content)
            if educ_match:
                coeff = float(educ_match.group(1))
                if -0.2 < coeff < 0: # Expected around -0.04 to -0.06
                    score += 5
                    feedback.append(f"Education coefficient ({coeff}) is negative as expected.")
                else:
                    feedback.append(f"Education coefficient ({coeff}) seems off (expected negative small).")
            
        except Exception as e:
            feedback.append(f"Error analyzing results file: {str(e)}")
    else:
        feedback.append("Model results file missing or empty.")

    # =========================================================
    # Check 2: Fitted Values CSV (40 points)
    # =========================================================
    fitted_info = files_info.get("fitted", {})
    if fitted_info.get("exists") and fitted_info.get("size", 0) > 100:
        score += 10
        feedback.append("Fitted values CSV exists.")
        
        try:
            with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as f:
                copy_from_env("/tmp/poisson_fitted.csv", f.name)
                fitted_vals = []
                with open(f.name, 'r') as csvfile:
                    reader = csv.reader(csvfile)
                    for row in reader:
                        # Gretl CSVs sometimes have headers or observation numbers
                        for cell in row:
                            try:
                                val = float(cell)
                                fitted_vals.append(val)
                            except ValueError:
                                continue
            os.unlink(f.name)
            
            # Validating data
            # Mroz dataset has 753 obs
            # If CSV has obs numbers + values, len might be 1506, or just values 753
            if len(fitted_vals) >= 753:
                score += 10
                feedback.append(f"Found sufficient data points ({len(fitted_vals)}).")
                
                # Calculate mean of fitted values
                # If the CSV contains observation indices (1, 2, 3...), we need to filter them out?
                # Gretl "store" command usually just dumps columns.
                # If we assume the agent saved just the fitted series, the mean should be close to 0.237
                # If they saved obs numbers, the mean will be huge.
                
                # Simple heuristic: filter for values < 10 (since kids < 6 count won't be huge)
                # and take mean of those
                plausible_vals = [v for v in fitted_vals if 0 <= v < 20]
                if plausible_vals:
                    mean_val = sum(plausible_vals) / len(plausible_vals)
                    # Ground truth mean is ~0.237
                    if 0.20 < mean_val < 0.28:
                        score += 20
                        feedback.append(f"Fitted values mean ({mean_val:.4f}) matches ground truth.")
                    else:
                        feedback.append(f"Fitted values mean ({mean_val:.4f}) deviates from expected (~0.237).")
                else:
                    feedback.append("Could not extract plausible fitted values from CSV.")
            else:
                feedback.append(f"Not enough data points in CSV ({len(fitted_vals)} found, expected >= 753).")
                
        except Exception as e:
            feedback.append(f"Error processing fitted CSV: {str(e)}")
    else:
        feedback.append("Fitted values CSV missing.")

    # =========================================================
    # Check 3: Dispersion Test (30 points)
    # =========================================================
    test_info = files_info.get("test", {})
    if test_info.get("exists") and test_info.get("size", 0) > 20:
        score += 10
        feedback.append("Dispersion test output exists.")
        
        try:
            with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f:
                copy_from_env("/tmp/dispersion_test.txt", f.name)
                with open(f.name, 'r', encoding='utf-8', errors='ignore') as rf:
                    content = rf.read()
            os.unlink(f.name)
            
            # Keywords for dispersion test
            keywords = ["Overdispersion", "dispersion", "Null hypothesis: E(y) = Var(y)", "Auxiliary regression"]
            if any(k in content for k in keywords):
                score += 20
                feedback.append("Dispersion test content verified.")
            else:
                feedback.append("Dispersion test file content does not look like a test result.")
                
        except Exception as e:
            feedback.append(f"Error reading dispersion test file: {str(e)}")
    else:
        feedback.append("Dispersion test file missing.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }