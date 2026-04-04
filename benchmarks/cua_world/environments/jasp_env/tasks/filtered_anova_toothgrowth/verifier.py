#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_filtered_anova_toothgrowth(traj, env_info, task_info):
    """
    Verifies the filtered ANOVA task.
    
    Criteria:
    1. JASP file exists and is valid.
    2. JASP analysis contains One-Way ANOVA.
    3. Correct Mean value in text report (7.98 vs 10.60).
    4. Correct p-value in text report (< 0.001).
    5. Filter usage (verified by the mean value - mean of 7.98 is only possible if OJ is excluded).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    metadata = task_info.get('metadata', {})
    target_mean = metadata.get('target_mean', 7.98)
    tolerance = metadata.get('target_mean_tolerance', 0.1)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Task Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

    # 2. Verify JASP File Existence and Structure (40 pts)
    jasp_exists = task_result.get("jasp_file_exists", False)
    jasp_created = task_result.get("jasp_file_created_during", False)
    
    if jasp_exists and jasp_created:
        score += 20
        feedback_parts.append("JASP file created.")
        
        # Analyze JASP file content
        with tempfile.NamedTemporaryFile(suffix=".jasp") as jasp_tmp:
            try:
                copy_from_env("/home/ga/Documents/JASP/VC_Dose_Analysis.jasp", jasp_tmp.name)
                
                if not zipfile.is_zipfile(jasp_tmp.name):
                    feedback_parts.append("JASP file is not a valid zip archive.")
                else:
                    score += 10 # File is valid structure
                    # Inspect internal JSONs for "OneWayANOVA" and "levene"
                    found_anova = False
                    found_levene = False
                    found_descriptives = False
                    
                    with zipfile.ZipFile(jasp_tmp.name, 'r') as z:
                        # JASP structure usually has an 'index.html' or JSONs in subfolders
                        # We search for analysis specifications in any JSON file
                        for filename in z.namelist():
                            if filename.endswith(".json"):
                                try:
                                    content = z.read(filename).decode('utf-8', errors='ignore')
                                    if "OneWayANOVA" in content or "anovaOneWay" in content:
                                        found_anova = True
                                    if "homogeneity" in content.lower() or "levene" in content.lower():
                                        found_levene = True
                                    if "descriptives" in content.lower():
                                        found_descriptives = True
                                except:
                                    pass
                    
                    if found_anova:
                        score += 10
                        feedback_parts.append("One-Way ANOVA analysis found in file.")
                    else:
                        feedback_parts.append("No One-Way ANOVA found in JASP file.")
                        
                    if found_levene:
                        score += 5
                        feedback_parts.append("Homogeneity tests enabled.")
                        
                    if found_descriptives:
                        score += 5
                        feedback_parts.append("Descriptives enabled.")
                        
            except Exception as e:
                feedback_parts.append(f"Error inspecting JASP file: {str(e)}")
    else:
        feedback_parts.append("JASP file not found or not created during task.")

    # 3. Verify Report Content (Mean and P-value) (50 pts)
    # The mean proves if they filtered correctly.
    # Mean of 0.5 dose for VC only is ~7.98.
    # Mean of 0.5 dose for OJ+VC is ~10.60.
    
    report_exists = task_result.get("report_file_exists", False)
    if report_exists:
        score += 10
        feedback_parts.append("Report file exists.")
        
        with tempfile.NamedTemporaryFile(suffix=".txt") as report_tmp:
            try:
                copy_from_env("/home/ga/Documents/JASP/vc_means.txt", report_tmp.name)
                with open(report_tmp.name, 'r') as f:
                    content = f.read()
                
                # Extract numerical values
                # Look for patterns like "Mean: 7.98" or "7.98"
                numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
                float_numbers = [float(n) for n in numbers]
                
                # Check for target mean (VC only)
                found_target_mean = False
                found_wrong_mean = False
                found_p_value = False
                
                for num in float_numbers:
                    if abs(num - target_mean) < tolerance:
                        found_target_mean = True
                    if abs(num - 10.60) < tolerance:
                        found_wrong_mean = True
                    # P-value for dose effect in VC group is extremely small (< 0.001)
                    # Often reported as 0.000 or <.001
                    if num < 0.01 and num >= 0.0:
                        found_p_value = True
                        
                # Check for "p < .001" string pattern explicitly if float check fails
                if not found_p_value and ("<.001" in content.replace(" ", "") or "<0.001" in content):
                    found_p_value = True

                if found_target_mean:
                    score += 30
                    feedback_parts.append("Correct mean value found (Dataset filtered correctly).")
                elif found_wrong_mean:
                    feedback_parts.append("Incorrect mean value found (Dataset likely NOT filtered).")
                else:
                    feedback_parts.append("Could not identify the correct mean value in report.")
                    
                if found_p_value:
                    score += 10
                    feedback_parts.append("P-value seems correct/significant.")
                    
            except Exception as e:
                feedback_parts.append(f"Error reading report file: {str(e)}")
    else:
        feedback_parts.append("Report file not found.")

    passed = (score >= 70) and ("Correct mean value found" in str(feedback_parts))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }