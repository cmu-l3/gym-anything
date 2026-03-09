#!/usr/bin/env python3
"""
Verifier for SVM Gender Prediction Task (JASP)

Checks:
1. JASP project file exists and is a valid ZIP.
2. JASP analysis configuration (parsed from internal JSON):
   - Algorithm: SVM
   - Target: Gender
   - Seed: 12345 (CRITICAL)
   - Split: 0.2 (20%)
3. Text report exists and contains plausible metrics.
"""

import json
import os
import zipfile
import re
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_svm_gender_prediction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Creation
    if result_data.get('jasp_file_created_during_task'):
        score += 10
        feedback_parts.append("JASP project file created")
    elif result_data.get('jasp_file_exists'):
        score += 5
        feedback_parts.append("JASP project file exists (but timestamp issue)")
    else:
        feedback_parts.append("JASP project file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Analyze JASP File Content (Deep Verification)
    # The .jasp file is a ZIP archive containing analysis specifications.
    jasp_config_correct = False
    seed_correct = False
    split_correct = False
    algorithm_correct = False
    vars_correct = False

    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    try:
        copy_from_env("/tmp/analysis_result.jasp", temp_jasp.name)
        
        if zipfile.is_zipfile(temp_jasp.name):
            with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                # JASP structure varies, but usually contains JSONs with analysis options.
                # We search all JSON files for relevant keys.
                
                # Helper to recursive search strings in JSON
                def search_json(obj, target_key=None, target_value=None):
                    found = False
                    if isinstance(obj, dict):
                        for k, v in obj.items():
                            if target_key and k == target_key and v == target_value:
                                return True
                            if search_json(v, target_key, target_value):
                                return True
                    elif isinstance(obj, list):
                        for item in obj:
                            if search_json(item, target_key, target_value):
                                return True
                    return False

                # Scan all files in zip
                full_text_content = ""
                for filename in z.namelist():
                    if filename.endswith('.json') or filename.endswith('.qml'):
                        try:
                            content = z.read(filename).decode('utf-8', errors='ignore')
                            full_text_content += content
                        except:
                            pass
                
                # String-based heuristics if JSON parsing is too complex due to JASP internal structure changes
                # Check Algorithm
                if "mlClassificationSvm" in full_text_content or "Support Vector Machine" in full_text_content:
                    algorithm_correct = True
                    score += 15
                    feedback_parts.append("SVM algorithm selected")
                
                # Check Seed (CRITICAL)
                if '"seed":12345' in full_text_content or '"seed": 12345' in full_text_content:
                    seed_correct = True
                    score += 20
                    feedback_parts.append("Reproducibility seed (12345) correctly set")
                else:
                    feedback_parts.append("Incorrect or missing random seed")

                # Check Split (20% test set means 0.2)
                # JASP might store this as "testSetRatio":0.2 or similar
                if '0.2' in full_text_content and ('test' in full_text_content.lower() or 'holdout' in full_text_content.lower()):
                    split_correct = True
                    score += 15
                    feedback_parts.append("Data split (20%) configured")
                
                # Check Variables
                if "Gender" in full_text_content and "Agreeableness" in full_text_content:
                    vars_correct = True
                    score += 10
                    feedback_parts.append("Variables assigned correctly")

    except Exception as e:
        feedback_parts.append(f"Could not analyze JASP file structure: {str(e)}")
    finally:
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)

    # 4. Check Text Report
    report_content = result_data.get('report_content', '')
    report_score = 0
    if result_data.get('report_file_created_during_task') and len(report_content) > 5:
        report_score += 10
        feedback_parts.append("Report file created")
        
        # Check for numeric values (AUC, counts)
        # We don't have exact ground truth without running JASP, but we expect reasonable values.
        # AUC for Big5->Gender is typically 0.60 - 0.75.
        
        # Find any float resembling AUC
        auc_candidates = re.findall(r"0\.\d+", report_content)
        valid_auc = any(0.5 <= float(x) <= 0.85 for x in auc_candidates)
        
        # Find integers for confusion matrix
        integers = re.findall(r"\b\d+\b", report_content)
        has_counts = len(integers) >= 2
        
        if valid_auc:
            report_score += 10
            feedback_parts.append("Report contains valid AUC range")
        if has_counts:
            report_score += 10
            feedback_parts.append("Report contains confusion matrix counts")
            
    else:
        feedback_parts.append("Report file missing or empty")
    
    score += report_score

    # 5. Final validation
    # Pass if JASP file is valid, seed is set, algorithm is correct, and report exists
    passed = (algorithm_correct and seed_correct and result_data.get('jasp_file_created_during_task'))
    
    # Adjust score if essential criteria fail
    if not seed_correct:
        score = min(score, 50)  # Seed is critical for this task
    
    return {
        "passed": passed and score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }