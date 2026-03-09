#!/usr/bin/env python3
"""
Verifier for Cox Regression Churn Task.

Criteria:
1. JASP project file (.jasp) created and valid.
2. JASP project contains Cox Regression analysis (checked via zip inspection).
3. Text report exists and contains correct Hazard Ratio and P-value.
4. VLM verification of trajectory (optional/secondary).
"""

import json
import os
import zipfile
import tempfile
import re
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cox_regression(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    
    # Define expected ranges
    # Two-year contract HR is typically very low (~0.02 - 0.1) relative to month-to-month
    hr_min = ground_truth.get('hr_two_year_min', 0.0)
    hr_max = ground_truth.get('hr_two_year_max', 0.2) 

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify JASP File (Existence & Structure)
    jasp_exists = result.get('jasp_file_exists', False)
    jasp_new = result.get('jasp_file_created_during_task', False)
    jasp_path = result.get('jasp_file_path')

    if jasp_exists and jasp_new:
        score += 10
        feedback_parts.append("JASP project file created")
        
        # Retrieve and inspect JASP file
        temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.zip') # .jasp is a zip
        try:
            copy_from_env(jasp_path, temp_jasp.name)
            
            # Check for Cox Regression in internal manifest/analysis
            try:
                with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                    file_list = z.namelist()
                    # Look for analysis results or state that indicates Cox Regression
                    # Simple heuristic: Check if any file inside contains "Cox" or "Survival"
                    found_cox = False
                    for fname in file_list:
                        if fname.endswith('.json') or fname.endswith('.qml'):
                            try:
                                content = z.read(fname).decode('utf-8', errors='ignore')
                                if 'survivalCoxRegression' in content or 'Cox Regression' in content:
                                    found_cox = True
                                    break
                            except:
                                pass
                    
                    if found_cox:
                        score += 25
                        feedback_parts.append("Cox Regression analysis found in project")
                    else:
                        feedback_parts.append("Could not confirm Cox Regression in project file structure")

            except zipfile.BadZipFile:
                feedback_parts.append("Saved file is not a valid JASP archive")
                
        except Exception as e:
            feedback_parts.append(f"Failed to inspect JASP file: {e}")
        finally:
            if os.path.exists(temp_jasp.name):
                os.unlink(temp_jasp.name)
    elif jasp_exists:
        score += 5
        feedback_parts.append("JASP file exists but was not created during task")
    else:
        feedback_parts.append("JASP project file missing")

    # 3. Verify Report Content
    report_exists = result.get('report_exists', False)
    if report_exists:
        score += 10
        feedback_parts.append("Report file created")
        
        try:
            content_b64 = result.get('report_content_b64', '')
            content = base64.b64decode(content_b64).decode('utf-8')
            
            # Extract numbers (Hazard Ratio)
            # Look for patterns like "HR: 0.05" or "0.05" near "Two year"
            # We look for floating point numbers in the text
            floats = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", content)]
            
            # Check for HR in valid range
            hr_found = False
            for val in floats:
                if hr_min <= val <= hr_max:
                    hr_found = True
                    break
            
            if hr_found:
                score += 25
                feedback_parts.append("Report contains valid Hazard Ratio for Two-year contract")
            else:
                feedback_parts.append("Report values do not match expected Hazard Ratio range (approx 0.02 - 0.1)")

            # Check for Proportional Hazards interpretation
            # The global test usually has p < 0.05 for this dataset, meaning assumption violated
            lower_content = content.lower()
            if "violated" in lower_content or "not met" in lower_content or "reject" in lower_content:
                score += 15
                feedback_parts.append("Correctly identified assumption violation")
            elif "met" in lower_content or "satisfied" in lower_content:
                feedback_parts.append("Incorrect interpretation of Proportional Hazards assumption")
            else:
                feedback_parts.append("No interpretation of assumption found")
                
            # Check if p-value is mentioned
            if "p-value" in lower_content or "p <" in lower_content or "p =" in lower_content or "p=" in lower_content:
                score += 15
                feedback_parts.append("P-value mentioned")

        except Exception as e:
            feedback_parts.append(f"Error parsing report: {e}")
    else:
        feedback_parts.append("Report file missing")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }