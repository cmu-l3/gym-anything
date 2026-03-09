#!/usr/bin/env python3
"""
Verifier for lmm_sleep_analysis task.

Checks:
1. .jasp file exists and was created during the task.
2. .jasp file contains Linear Mixed Model analysis (via zip inspection).
3. Report text file contains the correct Fixed Effect coefficient (~1.58).
4. Report text file contains a valid AIC value.
"""

import json
import os
import re
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lmm_sleep_analysis(traj, env_info, task_info):
    """
    Verify Linear Mixed Model analysis of Sleep data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment connection failed (no copy_from_env)."}

    metadata = task_info.get('metadata', {})
    expected_coeff = metadata.get('expected_fixed_effect', 1.58)
    tolerance = metadata.get('tolerance', 0.1)
    
    score = 0
    feedback = []
    
    # =========================================================
    # 1. Retrieve Task Result JSON
    # =========================================================
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name
        copy_from_env("/tmp/task_result.json", temp_json)
        with open(temp_json, 'r') as f:
            result_data = json.load(f)
        os.unlink(temp_json)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

    # =========================================================
    # 2. Check JASP File Existence (10 pts)
    # =========================================================
    jasp_info = result_data.get('jasp_file', {})
    if jasp_info.get('exists') and jasp_info.get('created_during_task'):
        score += 10
        feedback.append("JASP analysis file saved.")
    else:
        feedback.append("JASP file not found or not saved during task.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # =========================================================
    # 3. Analyze JASP File Structure (40 pts)
    # =========================================================
    # We need to pull the actual .jasp file to inspect its contents
    try:
        temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix=".jasp").name
        copy_from_env(jasp_info.get('path'), temp_jasp)
        
        is_lmm = False
        has_random_effect = False
        
        if zipfile.is_zipfile(temp_jasp):
            with zipfile.ZipFile(temp_jasp, 'r') as z:
                # List files to debug structure if needed
                file_list = z.namelist()
                
                # Search for indication of Linear Mixed Model
                # Usually found in analysis options or results
                # We search for the string "LinearMixedModel" in JSON or HTML files
                content_found = False
                for filename in file_list:
                    if filename.endswith('.json') or filename.endswith('.html'):
                        try:
                            content = z.read(filename).decode('utf-8', errors='ignore')
                            if "LinearMixedModel" in content or "Linear Mixed Models" in content:
                                is_lmm = True
                            if "Random Effects" in content and "ID" in content:
                                # This is a heuristic; strictly parsing the JSON structure is better but schema varies
                                # Checking if 'ID' appears near 'random' context
                                has_random_effect = True
                        except:
                            pass
        
        os.unlink(temp_jasp)
        
        if is_lmm:
            score += 20
            feedback.append("Confirmed Linear Mixed Model analysis type.")
        else:
            feedback.append("Could not confirm 'Linear Mixed Model' inside the JASP file.")

        if has_random_effect:
            score += 20
            feedback.append("Confirmed Random Effects configuration.")
        else:
            feedback.append("Could not confirm Random Effects (ID) in JASP file.")
            
    except Exception as e:
        feedback.append(f"Failed to inspect JASP file content: {str(e)}")

    # =========================================================
    # 4. Check Report Content (50 pts)
    # =========================================================
    report_info = result_data.get('report_file', {})
    if report_info.get('exists'):
        content = report_info.get('content', '')
        
        # Check for Coefficient (25 pts)
        # Look for number close to 1.58
        numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
        coeff_found = False
        for num in numbers:
            try:
                val = float(num)
                if abs(val - expected_coeff) <= tolerance:
                    coeff_found = True
                    break
            except ValueError:
                continue
        
        if coeff_found:
            score += 25
            feedback.append(f"Correct fixed effect coefficient found (~{expected_coeff}).")
        else:
            feedback.append(f"Report does not contain the correct fixed effect coefficient (expected ~{expected_coeff}).")

        # Check for AIC (15 pts)
        # AIC for this model is typically around 104-107 depending on settings (REML vs ML)
        aic_found = False
        for num in numbers:
            try:
                val = float(num)
                if 90 <= val <= 120: # Broad range for AIC
                    aic_found = True
                    break
            except ValueError:
                continue
                
        if aic_found:
            score += 15
            feedback.append("AIC value reported.")
        else:
            feedback.append("Valid AIC value not found in report.")
            
        # Check for some text interpretation (10 pts)
        if len(content.split()) > 5:
            score += 10
            feedback.append("Interpretation text present.")
        else:
            feedback.append("Report text seems too short.")
            
    else:
        feedback.append("Report file not created.")

    # =========================================================
    # Final Result
    # =========================================================
    passed = (score >= 60) and ("Correct fixed effect" in " ".join(feedback))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }