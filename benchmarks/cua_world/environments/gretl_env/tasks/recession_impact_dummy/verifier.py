#!/usr/bin/env python3
"""
Verifier for recession_impact_dummy task.

Criteria:
1. Output file exists and was created during the task.
2. File contains Gretl OLS regression output.
3. Regression uses 'inf' as dependent variable.
4. Regression includes a dummy variable (likely named 'recession').
5. VLM verification of the workflow (creating variables).
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_recession_impact_dummy(traj, env_info, task_info):
    """
    Verify the recession analysis task.
    """
    # 1. Setup and retrieve data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Load output text file
    output_content = ""
    if result_data.get("output_exists"):
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/Documents/gretl_output/recession_results.txt", temp_txt.name)
            with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
                output_content = f.read()
        except Exception as e:
            logger.warning(f"Could not read output file content: {e}")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)

    # 2. Scoring Logic
    score = 0
    feedback_items = []
    
    # Criterion 1: File Existence & Freshness (20 pts)
    if result_data.get("output_exists") and result_data.get("file_created_during_task"):
        score += 20
        feedback_items.append("Output file created successfully.")
    elif result_data.get("output_exists"):
        score += 10
        feedback_items.append("Output file exists but timestamp is suspicious (pre-existing?).")
    else:
        return {"passed": False, "score": 0, "feedback": "No output file found."}

    # Criterion 2: File Content - Basic Validity (20 pts)
    # Check for Gretl regression markers
    if "Model" in output_content and "Dependent variable: inf" in output_content:
        score += 20
        feedback_items.append("Valid OLS regression output detected.")
    else:
        feedback_items.append("Output does not look like a Gretl OLS regression for 'inf'.")
        # If it's not a regression, we stop here
        return {"passed": False, "score": score, "feedback": " ".join(feedback_items)}

    # Criterion 3: Correct Independent Variables (30 pts)
    # We expect 'const' and a dummy variable. The dummy name might vary, but 'recession' is requested.
    # We also check that 'gdp' (the raw variable) is NOT an independent variable directly.
    
    lines = output_content.splitlines()
    vars_found = []
    recession_dummy_found = False
    
    # Regex to capture variable lines in Gretl output usually looks like:
    # "             coefficient   std. error   t-ratio   p-value "
    # followed by:
    # "  const       0.12345       0.01234      ..."
    # "  recession  -0.54321       0.11111      ..."
    
    for line in lines:
        stripped = line.strip()
        # Heuristic: line starts with variable name, follows with numbers
        parts = stripped.split()
        if len(parts) >= 5 and parts[0] in ['const', 'recession', 'dummy', 'dum', 'gdp_growth_neg']:
            vars_found.append(parts[0])
            if parts[0] != 'const':
                 recession_dummy_found = True

    if 'const' in output_content and recession_dummy_found:
        score += 30
        feedback_items.append("Regression includes constant and a derived variable.")
    else:
        feedback_items.append("Could not identify expected independent variables (const + dummy).")

    # Criterion 4: Coefficient Check (30 pts)
    # We expect the coefficient for the recession dummy to be negative (inflation drops in recession).
    # We extract the number following the variable name.
    
    coeff_valid = False
    for line in lines:
        parts = line.split()
        if len(parts) >= 2 and parts[0] != 'const':
            # This is likely our dummy variable
            try:
                coeff = float(parts[1])
                if coeff < 0:
                    coeff_valid = True
                    feedback_items.append(f"Recession coefficient ({coeff}) is negative as expected.")
                else:
                    feedback_items.append(f"Recession coefficient ({coeff}) is non-negative (unexpected).")
            except ValueError:
                continue
    
    if coeff_valid:
        score += 30
    
    # 3. Final Determination
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_items)
    }