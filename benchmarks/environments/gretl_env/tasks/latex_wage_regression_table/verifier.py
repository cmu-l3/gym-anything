#!/usr/bin/env python3
import json
import os
import tempfile
import re

def verify_latex_wage_regression_table(traj, env_info, task_info):
    """
    Verify the generated LaTeX regression table.
    
    Criteria:
    1. File exists and is not empty (20 pts)
    2. Valid LaTeX structure (tabular environment) (20 pts)
    3. Model 1 variables present (educ, exper) (10 pts)
    4. Model 2 variables present (metro) (15 pts)
    5. Model 3 variables present (female, black) (15 pts)
    6. Robust SE indication (20 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # Load metadata
    expected_path = task_info.get('metadata', {}).get('expected_output_path', 'wage_models.tex')

    # Create temp files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_tex = tempfile.NamedTemporaryFile(delete=False, suffix='.tex')
    
    try:
        # Get result JSON
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        output_exists = result_data.get('output_exists', False)
        
        if not output_exists:
            return {"passed": False, "score": 0, "feedback": "Output file wage_models.tex not found."}
            
        # Get the actual LaTeX file
        try:
            copy_from_env(expected_path, temp_tex.name)
            with open(temp_tex.name, 'r', encoding='utf-8', errors='ignore') as f:
                tex_content = f.read()
        except Exception as e:
            return {"passed": False, "score": 20, "feedback": f"File exists but could not be read: {str(e)}"}

        # --- scoring ---
        
        # Criterion 1: File exists (already checked)
        score += 20
        feedback.append("File exists.")

        # Criterion 2: Valid LaTeX structure
        if "\\begin{tabular}" in tex_content and "\\end{tabular}" in tex_content:
            score += 20
            feedback.append("Valid LaTeX table structure found.")
        else:
            feedback.append("Missing standard LaTeX table structure.")

        # Analyze Content for Models
        # We verify variable presence. In a side-by-side table, variables appear in the first column.
        # We assume if the variable is listed, it was included in at least one model.
        # To be more strict, we could count columns, but text parsing can be brittle.
        # Presence of variable names is a good proxy for intent.
        
        # Criterion 3: Model 1 Vars
        if "educ" in tex_content and "exper" in tex_content:
            score += 10
            feedback.append("Model 1 variables (educ, exper) found.")
        else:
            feedback.append("Missing basic variables (educ/exper).")

        # Criterion 4: Model 2 Vars
        if "metro" in tex_content:
            score += 15
            feedback.append("Model 2 variable (metro) found.")
        else:
            feedback.append("Missing Model 2 variable (metro).")

        # Criterion 5: Model 3 Vars
        if "female" in tex_content and "black" in tex_content:
            score += 15
            feedback.append("Model 3 variables (female, black) found.")
        else:
            feedback.append("Missing Model 3 variables (female/black).")

        # Criterion 6: Robust SE Check
        # Gretl typically outputs "Standard errors: Robust" or "Heteroskedasticity-consistent" in the notes
        # or it might label the SE rows differently.
        robust_indicators = ["Robust", "Heteroskedasticity", "HC1", "H.C."]
        found_robust = any(ind in tex_content for ind in robust_indicators)
        
        if found_robust:
            score += 20
            feedback.append("Robust standard error indication found.")
        else:
            # Fallback check: look for specific numbers if possible? 
            # Without running the regression myself here, I rely on the label.
            # If the user didn't select Robust, these labels won't appear.
            feedback.append("No indication of Robust Standard Errors found (expected 'Robust', 'HC1', etc).")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
        
    finally:
        # Cleanup
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_tex.name):
            os.unlink(temp_tex.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }