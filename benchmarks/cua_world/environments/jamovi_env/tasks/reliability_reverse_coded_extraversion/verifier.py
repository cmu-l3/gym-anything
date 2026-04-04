#!/usr/bin/env python3
"""
Verifier for reliability_reverse_coded_extraversion task.

Criteria:
1. OMV project file created/modified during task (10 pts)
2. Report text file created/modified during task (10 pts)
3. Report contains correct Cronbach's Alpha (~0.76) (40 pts)
   - If Alpha is ~ -0.36, user failed to reverse code (0 pts for this section)
4. Report contains correct Mean and SD (20 pts)
5. OMV file is a valid zip (Jamovi format) containing reliability analysis (20 pts)
"""

import json
import os
import re
import zipfile
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reliability_reverse_coded(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_alpha = metadata.get('expected_alpha', 0.76)
    alpha_tolerance = metadata.get('alpha_tolerance', 0.03)
    
    score = 0
    feedback = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check existence
    omv_exists = result_data.get("omv_exists", False)
    omv_fresh = result_data.get("omv_created_during_task", False)
    report_exists = result_data.get("report_exists", False)
    report_fresh = result_data.get("report_created_during_task", False)

    if omv_exists and omv_fresh:
        score += 10
        feedback.append("Jamovi project file saved.")
    else:
        feedback.append("Jamovi project file missing or not saved during task.")

    if report_exists and report_fresh:
        score += 10
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing.")

    # 2. Analyze Report Content
    if report_exists:
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(metadata.get('report_path'), temp_report.name)
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            # Find Alpha
            # Look for patterns like "Alpha: 0.76", "0.76", "α = 0.76"
            # We look for a float number between -1.0 and 1.0
            numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
            floats = []
            for n in numbers:
                try:
                    floats.append(float(n))
                except:
                    pass
            
            # Find the value closest to expected alpha
            best_alpha = -999
            min_diff = 999
            
            for val in floats:
                # Alpha is usually between 0 and 1 (or negative if reversed items missing)
                if -1.0 <= val <= 1.0:
                    diff = abs(val - expected_alpha)
                    if diff < min_diff:
                        min_diff = diff
                        best_alpha = val
            
            # Evaluate Alpha
            if min_diff <= alpha_tolerance:
                score += 40
                feedback.append(f"Cronbach's Alpha correct ({best_alpha}).")
            elif abs(best_alpha - (-0.36)) < 0.1:
                feedback.append(f"Cronbach's Alpha incorrect ({best_alpha}). It looks like you forgot to reverse-code items E1 and E2.")
            else:
                feedback.append(f"Cronbach's Alpha incorrect or not found. Best match: {best_alpha}. Expected: {expected_alpha}.")

            # Check for Mean/SD (Approx 4.19, 1.05)
            # We just check if these numbers appear vaguely in the text
            found_mean = any(abs(val - 4.19) < 0.15 for val in floats)
            found_sd = any(abs(val - 1.05) < 0.15 for val in floats)
            
            if found_mean and found_sd:
                score += 20
                feedback.append("Scale Mean and SD reported correctly.")
            elif found_mean or found_sd:
                score += 10
                feedback.append("Partial Mean/SD reported.")
            else:
                feedback.append("Scale Mean/SD not found in report.")
                
        except Exception as e:
            feedback.append(f"Error reading report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

    # 3. Analyze OMV File Structure
    # An OMV file is a ZIP. It should contain manifest/metadata indicating the analysis.
    if omv_exists:
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
        try:
            copy_from_env(metadata.get('omv_path'), temp_omv.name)
            
            if zipfile.is_zipfile(temp_omv.name):
                with zipfile.ZipFile(temp_omv.name, 'r') as z:
                    # List files to see if it looks like a jamovi project
                    namelist = z.namelist()
                    # A valid OMV usually has 'MANIFEST.MF' or 'meta' or 'index.html'
                    if any('meta' in n for n in namelist) or 'MANIFEST.MF' in namelist:
                        score += 20
                        feedback.append("Valid Jamovi project structure confirmed.")
                    else:
                        feedback.append("File is a zip but structure unclear.")
            else:
                feedback.append("Saved file is not a valid OMV/ZIP archive.")
                
        except Exception as e:
            feedback.append(f"Error analyzing OMV file: {e}")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }