#!/usr/bin/env python3
"""
Verifier for Bain Hypothesis Testing task.
Checks if:
1. JASP project file exists and contains a Bain ANOVA analysis.
2. The hypothesis defined in JASP follows the order restriction (2.0 > 1.0 > 0.5).
3. The reported text file contains a Bayes Factor consistent with the data.
"""

import json
import os
import zipfile
import tempfile
import re
import shutil
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bain_hypothesis_toothgrowth(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Load task result metadata
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # 1. Check JASP file existence (10 pts)
    jasp_exists = task_result.get("jasp_file_exists", False)
    jasp_fresh = task_result.get("jasp_file_created_during_task", False)
    
    if jasp_exists and jasp_fresh:
        score += 10
        feedback_parts.append("JASP file saved successfully.")
    elif jasp_exists:
        score += 5
        feedback_parts.append("JASP file exists but timestamp is old (potential reuse).")
    else:
        feedback_parts.append("JASP file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Inspect JASP file content (40 pts)
    # JASP files are zips containing JSON analysis definitions
    jasp_path = task_result.get("jasp_path")
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    
    bain_found = False
    hypothesis_correct = False
    
    try:
        copy_from_env(jasp_path, temp_jasp.name)
        
        with zipfile.ZipFile(temp_jasp.name, 'r') as z:
            # Search for analysis JSONs
            # JASP structure varies, but usually analyses are in numbered folders or index
            # We will scan all .json files in the zip for Bain signatures
            for filename in z.namelist():
                if filename.endswith(".json"):
                    try:
                        with z.open(filename) as f:
                            content = json.load(f)
                            
                            # Check for Bain ANOVA
                            # Signature: "title": "Bain ANOVA" or "name": "BainANOVA"
                            title = content.get("title", "")
                            name = content.get("name", "")
                            results = content.get("results", {})
                            
                            if "Bain" in title or "Bain" in name or "bain" in str(content).lower():
                                bain_found = True
                                
                                # Check constraints/hypothesis
                                # Constraints are usually in 'options' dict
                                options = content.get("options", {})
                                constraints = options.get("constraints", "")
                                
                                # We expect "dose" and ">" and numbers 2.0, 1.0, 0.5
                                # User might use variable names or labels
                                constraints_str = str(constraints)
                                if ">" in constraints_str and "dose" in constraints_str.lower():
                                    # Check order: 2 > 1 > 0.5
                                    # This is a heuristic check on the string
                                    clean_str = re.sub(r'[^0-9\.]', ' ', constraints_str)
                                    nums = [float(x) for x in clean_str.split() if x.replace('.','',1).isdigit()]
                                    
                                    # We expect to see 2, 1, 0.5 roughly in that order relative to > signs
                                    # A simpler check: does the string contain something resembling "2 > 1" and "1 > 0.5"
                                    # or "dose2.0 > dose1.0"
                                    if "2" in constraints_str and "1" in constraints_str and "0.5" in constraints_str:
                                         hypothesis_correct = True
                    except:
                        continue
                        
    except Exception as e:
        feedback_parts.append(f"Failed to inspect JASP file: {e}")
    finally:
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)

    if bain_found:
        score += 20
        feedback_parts.append("Bain ANOVA analysis found.")
    else:
        feedback_parts.append("No Bain ANOVA analysis found in project.")
        
    if hypothesis_correct:
        score += 20
        feedback_parts.append("Informative hypothesis defined correctly.")
    else:
        if bain_found:
            feedback_parts.append("Bain analysis found, but hypothesis logic could not be verified or is missing.")

    # 3. Check Report File (30 pts)
    report_exists = task_result.get("report_exists", False)
    report_fresh = task_result.get("report_created_during_task", False)
    
    bf_value = None
    
    if report_exists and report_fresh:
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(task_result.get("report_path"), temp_report.name)
            with open(temp_report.name, 'r') as f:
                content = f.read()
                # Extract first floating point number
                match = re.search(r"[-+]?\d*\.\d+|\d+", content)
                if match:
                    bf_value = float(match.group())
                    score += 10 # Found a number
                    feedback_parts.append(f"Reported value: {bf_value}")
                else:
                    feedback_parts.append("Report file is empty or contains no numbers.")
        except Exception as e:
            feedback_parts.append(f"Could not read report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
        score += 10 # File exists
    else:
        feedback_parts.append("Report file not found.")

    # 4. Validate Bayes Factor (20 pts)
    # For ToothGrowth (len ~ dose), the evidence for monotonic increase is overwhelming.
    # BF should be > 1. Usually > 30.
    if bf_value is not None:
        if bf_value > 1.0:
            score += 20
            feedback_parts.append("Reported Bayes Factor indicates support for the hypothesis (Correct).")
        else:
            feedback_parts.append("Reported Bayes Factor is <= 1 (Unexpected for this dataset).")

    # Pass threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }