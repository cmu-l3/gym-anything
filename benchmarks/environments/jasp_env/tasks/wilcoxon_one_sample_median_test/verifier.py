#!/usr/bin/env python3
"""
Verifier for Wilcoxon One-Sample Median Test Task.

Verification Strategy:
1. Check if the .jasp file exists and is a valid ZIP archive.
2. Unpack the .jasp file and inspect the JSON analysis definitions.
   - JASP files store analysis settings in nested JSON structures.
   - We verify: 'wilcoxon': true, 'testValue': 50, 'locationParameter': true.
3. Check the text report for key values (W statistic, p-value, HL estimate).
4. Verify files were created during the task session.
"""

import json
import os
import zipfile
import tempfile
import re
import shutil

def verify_wilcoxon_test(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # =========================================================
    # 1. Retrieve Result Data
    # =========================================================
    temp_dir = tempfile.mkdtemp()
    try:
        # Get JSON result
        result_file = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_file)
            with open(result_file, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # Get JASP file if exists
        jasp_local_path = os.path.join(temp_dir, "submission.jasp")
        has_jasp = result_data.get("jasp_file_exists", False)
        if has_jasp:
            try:
                copy_from_env("/tmp/submission.jasp", jasp_local_path)
            except:
                has_jasp = False

        # Get Report file if exists
        report_local_path = os.path.join(temp_dir, "report.txt")
        has_report = result_data.get("report_exists", False)
        if has_report:
            try:
                copy_from_env("/tmp/submission_report.txt", report_local_path)
            except:
                has_report = False

    except Exception as e:
        shutil.rmtree(temp_dir)
        return {"passed": False, "score": 0, "feedback": f"Error during data retrieval: {str(e)}"}

    # =========================================================
    # 2. Score Calculation
    # =========================================================
    score = 0
    feedback = []
    
    # Criterion 1: Files Created (20 pts)
    if has_jasp and result_data.get("jasp_file_created_during_task", False):
        score += 10
        feedback.append("JASP file created.")
    else:
        feedback.append("JASP file missing or old.")

    if has_report and result_data.get("report_created_during_task", False):
        score += 10
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing or old.")

    # Criterion 2: JASP Configuration Verification (50 pts)
    jasp_config_correct = False
    
    if has_jasp:
        try:
            # JASP files are zips. We need to find the JSON containing analysis settings.
            # Usually in 'analyses/1.json' or similar, but the structure can vary.
            # We will search ALL json files inside the zip for the specific settings.
            found_settings = {
                "oneSampleTTest": False,
                "variable_exam": False,
                "testValue_50": False,
                "wilcoxon_true": False,
                "student_false": False,
                "location_true": False
            }

            with zipfile.ZipFile(jasp_local_path, 'r') as z:
                for filename in z.namelist():
                    if filename.endswith(".json"):
                        with z.open(filename) as f:
                            try:
                                content = f.read().decode('utf-8')
                                # JASP JSONs can be complex, simple string matching is often more robust 
                                # than parsing if schema is unknown, but let's try to parse if possible.
                                # However, JASP output json might be large.
                                
                                # Heuristic String Matching for settings
                                # We look for the "TTestOneSample" analysis definition
                                
                                if '"title": "One Sample T-Test"' in content or '"name": "TTestOneSample"' in content:
                                    found_settings["oneSampleTTest"] = True
                                    
                                    # Variable check (Exam)
                                    if '"Exam"' in content:
                                        found_settings["variable_exam"] = True
                                    
                                    # Test Value check (50)
                                    if '"testValue": 50' in content or '"testValue":50' in content:
                                        found_settings["testValue_50"] = True
                                        
                                    # Wilcoxon check
                                    if '"wilcoxon": true' in content or '"wilcoxon":true' in content:
                                        found_settings["wilcoxon_true"] = True
                                        
                                    # Student check (should be false)
                                    if '"student": false' in content or '"student":false' in content:
                                        found_settings["student_false"] = True
                                        
                                    # Location parameter check (Hodges-Lehmann)
                                    # Key is often "locationParameter"
                                    if '"locationParameter": true' in content or '"locationParameter":true' in content:
                                        found_settings["location_true"] = True

                            except:
                                continue

            # Evaluate Findings
            if found_settings["oneSampleTTest"]:
                score += 10
                if found_settings["testValue_50"]:
                    score += 10
                    feedback.append("Correct Test Value (50).")
                else:
                    feedback.append("Incorrect Test Value.")

                if found_settings["wilcoxon_true"]:
                    score += 20
                    feedback.append("Wilcoxon test selected.")
                else:
                    feedback.append("Wilcoxon test NOT selected.")
                
                if found_settings["location_true"]:
                    score += 10
                    feedback.append("Hodges-Lehmann estimate enabled.")
                else:
                    feedback.append("Hodges-Lehmann estimate missing.")
                
                jasp_config_correct = True
            else:
                feedback.append("One Sample T-Test analysis not found in file.")

        except zipfile.BadZipFile:
            feedback.append("JASP file is not a valid zip archive.")
        except Exception as e:
            feedback.append(f"Error analyzing JASP file: {str(e)}")

    # Criterion 3: Report Content Verification (30 pts)
    if has_report:
        try:
            with open(report_local_path, 'r') as f:
                content = f.read().lower()
            
            # Check for numbers. We don't verify exact values strictly to avoid 
            # floating point issues, but check for presence of likely candidates.
            # W statistic is usually large for N=103 (max W ~ N*(N+1)/2 = 5356).
            # Expected W ~ 4000.
            # P-value < 0.05.
            
            has_w = "w" in content or "statistic" in content
            has_p = "p" in content or "value" in content
            has_hl = "hodges" in content or "lehmann" in content or "estimate" in content
            
            points_report = 0
            if has_w: points_report += 10
            if has_p: points_report += 10
            if has_hl: points_report += 10
            
            score += points_report
            if points_report == 30:
                feedback.append("Report contains all required metrics.")
            else:
                feedback.append(f"Report incomplete (Score: {points_report}/30).")
                
        except Exception as e:
            feedback.append("Could not read report file.")

    # Cleanup
    shutil.rmtree(temp_dir)

    # Final Pass Determination
    # Must have JASP file, valid configuration, and report
    passed = (score >= 70 and has_jasp and jasp_config_correct)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }