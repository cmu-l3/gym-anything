#!/usr/bin/env python3
"""
Verifier for log_log_regression_toothgrowth task.

Criteria:
1. OMV project file exists and was created during the task.
2. OMV project file contains the computed variables 'ln_len' and 'ln_dose'.
3. Report file exists and contains the correct slope coefficient (approx 0.584).
4. Jamovi was running.
"""

import json
import os
import zipfile
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_log_log_regression(traj, env_info, task_info):
    """
    Verifies the log-log regression task results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_slope = metadata.get('expected_slope', 0.584)
    tolerance = metadata.get('slope_tolerance', 0.05)
    
    score = 0
    feedback_parts = []
    
    # Retrieve result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 1. Verify OMV File Existence and Creation (20 pts)
    omv_exists = result.get("omv_exists", False)
    omv_created = result.get("omv_created_during_task", False)
    omv_path = result.get("omv_path", "")

    if omv_exists:
        if omv_created:
            score += 20
            feedback_parts.append("Project file saved correctly.")
        else:
            score += 10
            feedback_parts.append("Project file exists but was not modified/created during task.")
    else:
        feedback_parts.append("Project file (PowerLaw_Analysis.omv) not found.")

    # 2. Verify Computed Variables in OMV (30 pts)
    # Jamovi .omv files are ZIP archives. We check the internal metadata for variable definitions.
    vars_found = False
    if omv_exists and omv_path:
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
        try:
            copy_from_env(omv_path, temp_omv.name)
            if zipfile.is_zipfile(temp_omv.name):
                with zipfile.ZipFile(temp_omv.name, 'r') as z:
                    # Search for variable names in any json/yaml/xml files in the archive
                    # Usually in META-INF or data definitions. 
                    # Simpler approach: Read typical metadata files as text
                    found_ln_len = False
                    found_ln_dose = False
                    
                    # Iterate through files in zip to find metadata containing variable names
                    for filename in z.namelist():
                        if filename.endswith('json') or filename.endswith('yaml') or 'meta' in filename.lower():
                            try:
                                with z.open(filename) as f:
                                    content = f.read().decode('utf-8', errors='ignore')
                                    if 'ln_len' in content:
                                        found_ln_len = True
                                    if 'ln_dose' in content:
                                        found_ln_dose = True
                            except:
                                continue
                    
                    if found_ln_len and found_ln_dose:
                        score += 30
                        vars_found = True
                        feedback_parts.append("Computed variables (ln_len, ln_dose) found in project.")
                    elif found_ln_len or found_ln_dose:
                        score += 15
                        feedback_parts.append("Only one of the computed variables was found.")
                    else:
                        feedback_parts.append("Computed variables not detected in project file.")
            else:
                feedback_parts.append("Project file is not a valid OMV archive.")
        except Exception as e:
            feedback_parts.append(f"Failed to inspect OMV file: {str(e)}")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)

    # 3. Verify Reported Slope Value (40 pts)
    report_exists = result.get("report_exists", False)
    report_content = result.get("report_content", "")
    
    slope_correct = False
    if report_exists:
        try:
            # Extract float from string (handle potential extra text)
            # Regex to find a floating point number
            match = re.search(r"[-+]?\d*\.\d+|\d+", report_content)
            if match:
                val = float(match.group())
                if abs(val - expected_slope) <= tolerance:
                    score += 40
                    slope_correct = True
                    feedback_parts.append(f"Reported slope ({val}) is correct.")
                else:
                    feedback_parts.append(f"Reported slope ({val}) is incorrect. Expected ~{expected_slope}.")
            else:
                feedback_parts.append("Report file is empty or contains no number.")
        except ValueError:
            feedback_parts.append("Could not parse number from report.")
    else:
        feedback_parts.append("Report file (elasticity_report.txt) not found.")

    # 4. App Running (10 pts)
    if result.get("app_was_running", False):
        score += 10
        feedback_parts.append("Jamovi was running.")
    else:
        feedback_parts.append("Jamovi closed unexpectedly.")

    # Determine Pass/Fail
    # Must have created file, found variables, AND got the right answer
    passed = (omv_created and vars_found and slope_correct)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }