#!/usr/bin/env python3
"""
Verifier for LDA Heart Disease Task.
Checks:
1. .jasp file exists and is a valid ZIP.
2. .jasp file contains evidence of Linear Discriminant Analysis.
3. Report file exists and contains reasonable accuracy numbers.
4. Anti-gaming: File timestamps and app state.
"""

import json
import os
import zipfile
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lda_heart_disease(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    score = 0
    feedback_parts = []
    max_score = 100

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check JASP File Existence and Creation (30 pts)
    if result.get("jasp_file_exists"):
        if result.get("jasp_created_during_task"):
            score += 30
            feedback_parts.append("JASP file created.")
        else:
            score += 10
            feedback_parts.append("JASP file exists but wasn't modified during task.")
    else:
        feedback_parts.append("JASP file not found.")

    # 3. Analyze JASP File Content (40 pts)
    # The .jasp file is a zip. We check for internal structure implying LDA.
    jasp_valid = False
    if result.get("jasp_file_exists"):
        temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix=".zip")
        try:
            copy_from_env("/tmp/verification_file.jasp", temp_jasp.name)
            
            if zipfile.is_zipfile(temp_jasp.name):
                with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                    # List all files in archive
                    file_list = z.namelist()
                    
                    # Check for analysis definitions
                    # JASP usually stores analysis meta in JSON files inside
                    found_lda = False
                    for filename in file_list:
                        if filename.endswith(".json"):
                            try:
                                content = z.read(filename).decode('utf-8', errors='ignore')
                                if "LinearDiscriminantAnalysis" in content or "MachineLearningClassificationLDA" in content:
                                    found_lda = True
                                    break
                            except:
                                continue
                    
                    if found_lda:
                        score += 40
                        jasp_valid = True
                        feedback_parts.append("Confirmed LDA analysis inside JASP file.")
                    else:
                        feedback_parts.append("JASP file is valid but LDA analysis not detected in metadata.")
                        # Partial credit if it's a valid JASP file
                        score += 10
            else:
                feedback_parts.append("JASP file is not a valid ZIP archive.")
        except Exception as e:
            feedback_parts.append(f"Failed to inspect JASP file: {str(e)}")
        finally:
            if os.path.exists(temp_jasp.name):
                os.unlink(temp_jasp.name)

    # 4. Check Text Report Content (20 pts)
    report_content = result.get("report_content", "")
    if result.get("report_exists") and report_content:
        score += 10
        
        # Check for accuracy (0.0 - 1.0 or percentage)
        # Regex for float between 0 and 1 or 0 and 100
        accuracy_match = re.search(r"0\.\d+|[1-9]\d?(\.\d+)?%", report_content)
        
        # Check for integer (False Negatives)
        # Just looking for digits
        digit_match = re.search(r"\d+", report_content)
        
        if accuracy_match and digit_match:
            score += 10
            feedback_parts.append("Report contains numerical results.")
        else:
            feedback_parts.append("Report exists but missing clear numerical values.")
    else:
        feedback_parts.append("Text report missing.")

    # 5. App State (10 pts)
    if result.get("app_running"):
        score += 10
        feedback_parts.append("JASP was running at end of task.")

    passed = (score >= 70) and jasp_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }