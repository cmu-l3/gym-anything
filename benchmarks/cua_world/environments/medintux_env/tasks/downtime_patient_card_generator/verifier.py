#!/usr/bin/env python3
"""
Verifier for Downtime Patient Card Generator task.
Checks if HTML cards were generated correctly from the database and schedule.
"""

import json
import os
import tarfile
import tempfile
import re
import shutil

def verify_downtime_cards(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback = []
    
    # Create temp dir for analysis
    temp_dir = tempfile.mkdtemp()
    
    try:
        # Retrieve the package
        package_path = os.path.join(temp_dir, "verification_package.tar.gz")
        try:
            copy_from_env("/tmp/verification_package.tar.gz", package_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
            
        # Extract
        with tarfile.open(package_path, "r:gz") as tar:
            tar.extractall(path=temp_dir)
            
        # Load metadata
        with open(os.path.join(temp_dir, "task_result.json"), 'r') as f:
            result_meta = json.load(f)
            
        # Load ground truth
        gt_path = os.path.join(temp_dir, "ground_truth.json")
        if not os.path.exists(gt_path):
            return {"passed": False, "score": 0, "feedback": "Ground truth file missing from export."}
            
        with open(gt_path, 'r') as f:
            ground_truth = json.load(f)

        # ---------------------------------------------------------
        # Scoring Criteria
        # ---------------------------------------------------------

        # 1. Basic Execution (30 pts)
        if result_meta.get("output_dir_exists"):
            score += 10
            feedback.append("Output directory created.")
        else:
            feedback.append("Output directory missing.")

        files_generated = result_meta.get("files_generated_count", 0)
        expected_count = len(ground_truth)
        
        if files_generated == expected_count:
            score += 20
            feedback.append(f"Correct number of files generated ({files_generated}).")
        elif files_generated > 0:
            score += 10
            feedback.append(f"Some files generated ({files_generated}/{expected_count}).")
        else:
            feedback.append("No files generated.")
            return {"passed": False, "score": score, "feedback": " ".join(feedback)}

        if not result_meta.get("created_during_task", False):
            feedback.append("WARNING: Files appear to have old timestamps (not created during task).")
            # Severe penalty for gaming
            score = 0 
            return {"passed": False, "score": 0, "feedback": "Files were not created during the task window."}

        # 2. Content Verification (70 pts)
        # We check each expected patient against the generated files
        
        patient_scores = 0
        pts_per_patient = 70 / expected_count
        
        for patient in ground_truth:
            expected_filename = patient['filename']
            file_path = os.path.join(temp_dir, expected_filename)
            
            patient_passed = True
            file_feedback = []
            
            # Check A: Filename existence
            if not os.path.exists(file_path):
                # Try finding a file that roughly matches if exact name failed
                # (e.g. strict time format difference 0900 vs 900)
                candidates = [f for f in os.listdir(temp_dir) if patient['lastname'] in f and f.endswith('.html')]
                if len(candidates) == 1:
                    file_path = os.path.join(temp_dir, candidates[0])
                    file_feedback.append(f"Filename mismatch but found likely candidate: {candidates[0]}")
                    # Partial penalty for wrong filename format
                    patient_scores -= (pts_per_patient * 0.2) 
                else:
                    patient_passed = False
                    file_feedback.append(f"File {expected_filename} not found.")
            
            if patient_passed:
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    
                # Check B: Name Presence
                if patient['lastname'] not in content or patient['firstname'] not in content:
                    patient_passed = False
                    file_feedback.append("Name missing in HTML.")
                
                # Check C: Age Calculation
                # Look for the age number
                if str(patient['age']) not in content:
                    patient_passed = False
                    file_feedback.append(f"Age {patient['age']} not found.")
                
                # Check D: Phone handling
                expected_phone = patient['phone']
                if expected_phone == "N/A":
                    # Look for N/A or generic indicator
                    if "N/A" not in content and "Non renseigné" not in content:
                        patient_passed = False
                        file_feedback.append("Missing phone not handled correctly (expected 'N/A').")
                else:
                    if expected_phone not in content:
                        patient_passed = False
                        file_feedback.append(f"Phone {expected_phone} missing.")

            if patient_passed:
                patient_scores += pts_per_patient
            else:
                feedback.append(f"Patient {patient['lastname']}: " + "; ".join(file_feedback))

        score += int(patient_scores)
        
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }