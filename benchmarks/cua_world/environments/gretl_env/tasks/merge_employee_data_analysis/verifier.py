#!/usr/bin/env python3
"""
Verifier for merge_employee_data_analysis task.

Criteria:
1. Merged GDT file exists and is valid (contains expected variables).
2. Regression results text file exists and contains OLS output.
3. Regression coefficients match expected logic (Wage gap analysis).
4. Files created during task window.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_employee_data_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result summary
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_summary = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result summary: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Merged Data File (30 points)
    if result_summary.get("merged_gdt_exists") and result_summary.get("merged_gdt_created_during_task"):
        # Analyze content
        temp_gdt = tempfile.NamedTemporaryFile(delete=False, suffix='.gdt')
        try:
            copy_from_env("/home/ga/Documents/gretl_output/merged_data.gdt", temp_gdt.name)
            with open(temp_gdt.name, 'r', encoding='utf-8', errors='ignore') as f:
                gdt_content = f.read()
            
            # Check for XML tags defining variables
            required_vars = ["wage", "educ", "exper", "female"]
            vars_found = [v for v in required_vars if f'name="{v}"' in gdt_content]
            
            if len(vars_found) == 4:
                score += 30
                feedback_parts.append("Merged dataset contains all required variables.")
            else:
                score += 15
                feedback_parts.append(f"Merged dataset exists but missing variables: {set(required_vars) - set(vars_found)}")
        except Exception:
            feedback_parts.append("Failed to analyze merged dataset content.")
        finally:
            if os.path.exists(temp_gdt.name):
                os.unlink(temp_gdt.name)
    else:
        feedback_parts.append("Merged dataset file not found or not created during task.")

    # 2. Verify Regression Results (50 points)
    regression_valid = False
    if result_summary.get("results_txt_exists") and result_summary.get("results_txt_created_during_task"):
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/Documents/gretl_output/wage_gap_results.txt", temp_txt.name)
            with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
                txt_content = f.read()
            
            # Check for OLS signature
            if "Model" in txt_content and "Dependent variable: wage" in txt_content:
                score += 10
                feedback_parts.append("Regression output file format looks correct.")
                
                # Check coefficients (Real Data Verification)
                # Female coeff should be negative (wage gap)
                # Educ coeff should be positive
                
                # Regex to find coefficient for 'female'
                # Line format often:  female     -3.456    0.543    ...
                female_match = re.search(r'female\s+([-\d.]+)', txt_content)
                educ_match = re.search(r'educ\s+([-\d.]+)', txt_content)
                
                if female_match and educ_match:
                    female_coeff = float(female_match.group(1))
                    educ_coeff = float(educ_match.group(1))
                    
                    data_points = 0
                    if female_coeff < 0:
                        data_points += 20
                        feedback_parts.append(f"Female coefficient ({female_coeff}) has expected negative sign.")
                    else:
                        feedback_parts.append(f"Female coefficient ({female_coeff}) is positive (unexpected for this data).")
                        
                    if educ_coeff > 0:
                        data_points += 20
                        feedback_parts.append(f"Education coefficient ({educ_coeff}) has expected positive sign.")
                    else:
                        feedback_parts.append(f"Education coefficient ({educ_coeff}) is negative (unexpected).")
                        
                    score += data_points
                    if data_points == 40:
                        regression_valid = True
                else:
                    feedback_parts.append("Could not parse regression coefficients.")
            else:
                feedback_parts.append("Output file does not appear to be an OLS regression on 'wage'.")
        except Exception as e:
            feedback_parts.append(f"Error analyzing regression results: {e}")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)
    else:
        feedback_parts.append("Regression output file not found or not created during task.")

    # 3. App Running (10 points)
    if result_summary.get("app_was_running"):
        score += 10
    
    # 4. Anti-gaming / basic checks (10 points)
    if result_summary.get("merged_gdt_size", 0) > 1000 and result_summary.get("results_txt_size", 0) > 100:
        score += 10
    
    passed = (score >= 80) and regression_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }