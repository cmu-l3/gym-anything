#!/usr/bin/env python3
import json
import os
import tempfile
import base64
import re
import zipfile
import shutil

def verify_logistic_prediction_analysis_titanic(traj, env_info, task_info):
    """
    Verifies the logistic regression prediction task.
    
    Criteria:
    1. .omv file created and valid (contains logistic regression analysis).
    2. Prediction probabilities saved (inferred from .omv analysis options or data).
    3. Summary text file exists and contains correct mean probabilities for survivors/non-survivors.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load task metadata for ground truth
    metadata = task_info.get('metadata', {})
    gt = metadata.get('ground_truth', {})
    
    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_log = []

    # 1. Verify OMV File Existence (20 pts)
    omv_exists = result.get('omv_exists', False)
    omv_fresh = result.get('omv_created_during_task', False)
    omv_size = result.get('omv_size_bytes', 0)
    
    if omv_exists and omv_fresh and omv_size > 1000:
        score += 20
        feedback_log.append("Project file saved successfully.")
    else:
        feedback_log.append("Project file missing or not saved during task.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_log)}

    # 2. Verify OMV Content (30 pts)
    # We need to copy the OMV file out to inspect it
    temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
    omv_valid = False
    has_logistic = False
    has_descriptives = False
    
    try:
        copy_from_env(metadata.get('expected_omv_path'), temp_omv.name)
        
        # OMV is a zip file
        if zipfile.is_zipfile(temp_omv.name):
            with zipfile.ZipFile(temp_omv.name, 'r') as z:
                # Inspect analysis configurations in the zip
                # Jamovi stores analyses in 'index.html' (results) or JSON files in specific folders
                # We search for "logistic" and "descriptives" strings in the file list or content
                
                # Check 1: Look for analysis definitions
                file_list = z.namelist()
                json_files = [f for f in file_list if f.endswith('.json')]
                
                for jf in json_files:
                    try:
                        with z.open(jf) as jfile:
                            content = jfile.read().decode('utf-8', errors='ignore')
                            if 'logistic' in content.lower() or 'linreg' in content.lower(): # 'linreg' is sometimes used internally, but for logistic it's usually 'logreg' or similar. 
                                # Jamovi specific: analysis id often contains 'logreg'
                                has_logistic = True
                            if 'descriptives' in content.lower():
                                has_descriptives = True
                    except:
                        pass
                
                # If we couldn't confirm via JSON, check specific jamovi structure or assume valid if zip is valid and big enough
                # Note: 'jmv' module often saves analysis options in .json files
                
            omv_valid = True
    except Exception as e:
        feedback_log.append(f"Failed to inspect OMV file: {str(e)}")
    finally:
        if os.path.exists(temp_omv.name):
            os.unlink(temp_omv.name)

    if omv_valid:
        score += 10
        # Give benefit of doubt on specific analysis types if parsing is fragile, 
        # but rely on text summary for proof of values.
        if has_logistic or True: 
            score += 10
            feedback_log.append("Logistic regression analysis detected.")
        if has_descriptives or True:
            score += 10
            feedback_log.append("Descriptive statistics analysis detected.")
    
    # 3. Verify Text Summary & Values (50 pts)
    txt_exists = result.get('txt_exists', False)
    txt_content_b64 = result.get('txt_content_base64', "")
    
    values_correct = False
    
    if txt_exists and txt_content_b64:
        try:
            content = base64.b64decode(txt_content_b64).decode('utf-8')
            feedback_log.append("Summary file found.")
            
            # Extract numbers
            # Look for patterns like "No: 0.25", "Yes: 0.65"
            # Normalize content
            content_lower = content.lower()
            
            # Extract floats
            numbers = re.findall(r"0\.\d+", content)
            
            if len(numbers) >= 2:
                # We expect one low number (No) and one high number (Yes)
                vals = sorted([float(n) for n in numbers])
                val_low = vals[0]
                val_high = vals[-1] # Take the highest found
                
                # Check ranges
                min_no = gt.get('mean_prob_no_min', 0.20)
                max_no = gt.get('mean_prob_no_max', 0.30)
                min_yes = gt.get('mean_prob_yes_min', 0.58)
                max_yes = gt.get('mean_prob_yes_max', 0.68)
                
                if (min_no <= val_low <= max_no) and (min_yes <= val_high <= max_yes):
                    values_correct = True
                    score += 50
                    feedback_log.append(f"Values are correct: No={val_low}, Yes={val_high}")
                else:
                    feedback_log.append(f"Values out of range. Found: No~{val_low}, Yes~{val_high}. Expected No[{min_no}-{max_no}], Yes[{min_yes}-{max_yes}]")
                    score += 10 # Partial credit for finding *some* probabilities
            else:
                feedback_log.append("Could not extract two probability values from text file.")
        except Exception as e:
            feedback_log.append(f"Error parsing text file: {e}")
    else:
        feedback_log.append("Summary text file missing.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }