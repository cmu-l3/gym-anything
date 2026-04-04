#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_phillips_curve_table(traj, env_info, task_info):
    """
    Verify the Phillips Curve LaTeX table task.
    
    Criteria:
    1. Output file exists and is a valid LaTeX table.
    2. File was created during the task.
    3. Table contains 3 model columns.
    4. Coefficients for Model 3 match ground truth values.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Retrieve task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 2. Retrieve the agent's LaTeX output file
    agent_latex_path = "/home/ga/Documents/gretl_output/phillips_table.tex"
    temp_latex = tempfile.NamedTemporaryFile(delete=False, suffix='.tex')
    latex_content = ""
    
    if result_data.get("output_exists"):
        try:
            copy_from_env(agent_latex_path, temp_latex.name)
            with open(temp_latex.name, 'r', encoding='utf-8', errors='ignore') as f:
                latex_content = f.read()
        except Exception as e:
            logger.warning(f"Could not read agent output file: {e}")
        finally:
            if os.path.exists(temp_latex.name):
                os.unlink(temp_latex.name)

    # Scoring Setup
    score = 0
    feedback = []
    
    # Criterion 1: File Existence & Creation (20 pts)
    if result_data.get("output_exists"):
        score += 10
        if result_data.get("file_created_during_task"):
            score += 10
            feedback.append("Output file created successfully.")
        else:
            feedback.append("Output file exists but was not modified during task.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Criterion 2: LaTeX Format Validity (10 pts)
    if "\\begin{tabular}" in latex_content or "\\begin{table}" in latex_content:
        score += 10
        feedback.append("File contains LaTeX table structure.")
    else:
        feedback.append("File does not appear to be a valid LaTeX table.")

    # Criterion 3: Content Parsing & Coefficient Verification (70 pts)
    ground_truth = result_data.get("ground_truth", {})
    
    # We expect coefficients like:
    # Model 3 Inf Lag: ~0.6 to 0.8
    # Model 3 GDP Growth: ~0.08 to 0.15
    # Model 3 GDP Growth Lag: usually small/negative
    
    gt_inf_lag = ground_truth.get("model3_inf_lag")
    gt_growth = ground_truth.get("model3_gdp_growth")
    
    if gt_inf_lag is None:
        feedback.append("Warning: Ground truth generation failed. Verification may be limited.")
    
    # Robust Regex to find rows in the LaTeX table
    # Pattern looks for variable name, followed by 3 columns of numbers
    # Example: "gdp\_growth & & 0.123 & 0.098 \\" or similar
    
    # Check for presence of key variables
    if "gdp_growth" in latex_content or "gdp\\_growth" in latex_content:
        score += 10
        feedback.append("Variable 'gdp_growth' found in table.")
    else:
        feedback.append("Variable 'gdp_growth' NOT found in table.")

    # Verify column count (heuristic: look for lines with multiple ampersands)
    # A 3-model table usually has at least 3 ampersands (Var & M1 & M2 & M3 \\)
    ampersand_counts = [line.count('&') for line in latex_content.split('\n')]
    max_ampersands = max(ampersand_counts) if ampersand_counts else 0
    
    if max_ampersands >= 3:
        score += 10
        feedback.append("Table appears to have at least 3 model columns.")
    else:
        feedback.append(f"Table structure unclear (max columns found: {max_ampersands+1}). Expected 3 models.")

    # Numerical Verification
    # We try to find the coefficients for the 'gdp_growth' row.
    # The row should contain numbers. In a consolidated table, Model 2 and 3 have this var.
    # We look for the LAST number in the row (Model 3).
    
    # Regex explanation:
    # 1. (?:gdp\\_growth|gdp_growth) -> match variable name
    # 2. .*? -> skip align characters
    # 3. ([0-9]+\.[0-9]+) -> capture a float
    # We search for all floats in that line.
    
    coeffs_found = False
    
    for line in latex_content.split('\n'):
        if "gdp_growth" in line.replace("\\_", "_") and "(-1)" not in line:
            # Found the main growth variable row
            numbers = re.findall(r'-?\d+\.\d+', line)
            if len(numbers) >= 2: # Should be present in Model 2 and 3
                try:
                    # The last number is likely Model 3
                    val_m3 = float(numbers[-1])
                    coeffs_found = True
                    
                    if gt_growth is not None:
                        # Tolerance check (LaTeX output might be rounded to 3-4 decimals)
                        if abs(val_m3 - gt_growth) < 0.02:
                            score += 25
                            feedback.append(f"Model 3 'gdp_growth' coefficient match ({val_m3}).")
                        else:
                            feedback.append(f"Model 3 'gdp_growth' coefficient mismatch. Expected ~{gt_growth}, found {val_m3}.")
                            score += 5 # Partial credit for finding number
                except ValueError:
                    pass
            break
            
    if not coeffs_found:
        feedback.append("Could not parse 'gdp_growth' coefficients from table.")

    # Check for lag of inflation (present in all models)
    for line in latex_content.split('\n'):
        if "inf" in line and "(-1)" in line: # inf(-1) row
            numbers = re.findall(r'-?\d+\.\d+', line)
            if len(numbers) >= 3: # Should be in all 3 models
                try:
                    val_m3 = float(numbers[-1])
                    if gt_inf_lag is not None:
                        if abs(val_m3 - gt_inf_lag) < 0.02:
                            score += 25
                            feedback.append(f"Model 3 'inf(-1)' coefficient match ({val_m3}).")
                        else:
                            feedback.append(f"Model 3 'inf(-1)' mismatch. Expected ~{gt_inf_lag}, found {val_m3}.")
                except ValueError:
                    pass
            break

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }