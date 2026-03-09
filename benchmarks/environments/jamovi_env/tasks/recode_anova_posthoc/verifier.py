#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import re
import shutil
from typing import Dict, Any

def verify_recode_anova_posthoc(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the agent:
    1. Created the .omv file.
    2. Created the 'AnxietyLevel' variable with correct groups.
    3. Ran the One-Way ANOVA with correct F-statistic.
    4. Included Post-Hoc tests (Tukey).
    5. Checked Assumptions (Levene/Shapiro).
    """
    
    # 1. Setup & Imports
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    score = 0
    feedback = []
    
    # Temporary directory for processing
    with tempfile.TemporaryDirectory() as temp_dir:
        result_json_path = os.path.join(temp_dir, "task_result.json")
        omv_path = os.path.join(temp_dir, "output.omv")
        
        # 2. Fetch Files
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # Check basic file existence criteria
        if not task_result.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Result file 'ExamAnxietyRecoded.omv' was not created."}
            
        if not task_result.get("output_modified_during_task", False):
            return {"passed": False, "score": 0, "feedback": "Result file exists but was not modified during the task."}
        
        score += 10 # File exists and is new
        
        # Retrieve the .omv file
        try:
            copy_from_env("/tmp/output.omv", omv_path)
        except Exception as e:
             return {"passed": False, "score": score, "feedback": f"Failed to retrieve .omv file: {str(e)}"}

        # 3. Analyze .omv Content
        # .omv is a zip file containing analysis results (usually in index.html or JSONs)
        try:
            if not zipfile.is_zipfile(omv_path):
                 return {"passed": False, "score": score, "feedback": "Output file is not a valid Jamovi (.omv) archive."}
            
            with zipfile.ZipFile(omv_path, 'r') as z:
                file_list = z.namelist()
                
                # Check for Analysis HTML (contains the tables)
                html_content = ""
                if "index.html" in file_list:
                    with z.open("index.html") as f:
                        html_content = f.read().decode('utf-8', errors='ignore')
                
                # Check for metadata/manifest (contains variable list)
                meta_content = ""
                # Try common metadata locations
                meta_files = [f for f in file_list if "meta" in f or "MANIFEST" in f]
                for mf in meta_files:
                    with z.open(mf) as f:
                        meta_content += f.read().decode('utf-8', errors='ignore')

                # Also read the raw data manifest if available (often in data.bin metadata or distinct json)
                # We'll rely mostly on the HTML output which reflects the active analysis
                
                # --- VERIFICATION CRITERIA ---
                
                # A. Variable Creation (AnxietyLevel)
                # We check if "AnxietyLevel" appears in the output or metadata
                if "AnxietyLevel" in html_content or "AnxietyLevel" in meta_content:
                    score += 20
                    feedback.append("Variable 'AnxietyLevel' detected.")
                else:
                    feedback.append("Variable 'AnxietyLevel' NOT found in output.")
                
                # B. ANOVA Presence
                if "One-Way ANOVA" in html_content:
                    score += 15
                    feedback.append("One-Way ANOVA analysis found.")
                else:
                    feedback.append("One-Way ANOVA analysis NOT found.")
                
                # C. F-Statistic Verification (Content Accuracy)
                ground_truth = task_result.get("ground_truth", {})
                expected_f = ground_truth.get("f_statistic")
                
                # Search for F value in HTML using regex
                # Pattern looks for F value followed by df or p-value in table structure
                # This is heuristic but effective for standard tables
                f_found = False
                if expected_f:
                    # Look for number close to expected_f
                    # Simplistic check: is the string form of the number (to 1 or 2 decimals) present near "F"
                    target_str = f"{expected_f:.2f}" # e.g. "5.43"
                    if target_str in html_content:
                        score += 10
                        f_found = True
                        feedback.append(f"Correct F-statistic ({target_str}) found in results.")
                    else:
                        feedback.append(f"Expected F-statistic ({target_str}) not found in results.")
                
                # D. Post-Hoc Tests
                if "Tukey" in html_content and "Post Hoc Comparisons" in html_content:
                    score += 10
                    feedback.append("Tukey Post-Hoc tests found.")
                else:
                    feedback.append("Tukey Post-Hoc tests missing.")
                
                # E. Assumption Checks
                if "Shapiro-Wilk" in html_content:
                    score += 5
                    feedback.append("Normality test (Shapiro-Wilk) found.")
                else:
                    feedback.append("Shapiro-Wilk test missing.")
                    
                if "Homogeneity of Variances" in html_content or "Levene" in html_content:
                    score += 5
                    feedback.append("Homogeneity test (Levene's) found.")
                else:
                    feedback.append("Homogeneity test missing.")

                # F. Descriptives
                if "Descriptives" in html_content and "Mean" in html_content and "SD" in html_content:
                    score += 10
                    feedback.append("Group descriptives table found.")
                else:
                    feedback.append("Descriptives table missing.")
                
                # G. Recoding Logic Verification (Indirect)
                # If F-stat matches, the recoding was likely correct.
                if f_found:
                    score += 15
                    feedback.append("Recoding logic confirmed via F-statistic match.")
                else:
                    feedback.append("Recoding logic could not be confirmed (F-stat mismatch).")

        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Error analyzing output file: {str(e)}"}

    # Final Score Calculation
    # Pass threshold: 60 points AND 'AnxietyLevel' created AND ANOVA present
    passed = (score >= 60) and ("Variable 'AnxietyLevel' detected." in feedback) and ("One-Way ANOVA analysis found." in feedback)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }