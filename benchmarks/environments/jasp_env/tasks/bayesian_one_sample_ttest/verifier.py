#!/usr/bin/env python3
"""
Verifier for Bayesian One-Sample T-Test task.
Checks the saved .jasp file (ZIP archive) for correct analysis configuration and results.
"""

import os
import sys
import json
import zipfile
import tempfile
import re
import logging
import shutil
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bayesian_one_sample_ttest(traj, env_info, task_info):
    """
    Verify that the agent performed the Bayesian One-Sample T-Test correctly.
    
    Criteria:
    1. Output .jasp file exists and is valid (10 pts)
    2. File created during task session (anti-gaming) (10 pts)
    3. Correct analysis type (Bayesian One-Sample) (15 pts)
    4. Correct variable (Exam) (15 pts)
    5. Correct test value (50) (15 pts)
    6. BF10 value indicates evidence for H1 (15 pts)
    7. Descriptives and plots enabled (10 pts)
    8. VLM verification of workflow (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_path', '/home/ga/Documents/JASP/ExamBayesianOneSample.jasp')
    
    # ------------------------------------------------------------------
    # Step 1: Check Metadata & File Existence
    # ------------------------------------------------------------------
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output .jasp file not found."}
    
    score += 10
    feedback_parts.append("Output file exists")

    if task_result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp invalid (created before task?)")

    # ------------------------------------------------------------------
    # Step 2: Analyze JASP File Content
    # ------------------------------------------------------------------
    temp_jasp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    analysis_correct = False
    variable_correct = False
    test_value_correct = False
    bf_correct = False
    settings_correct = False
    
    try:
        copy_from_env(expected_path, temp_jasp_file.name)
        
        if not zipfile.is_zipfile(temp_jasp_file.name):
            feedback_parts.append("Output file is not a valid JASP/ZIP archive")
        else:
            with zipfile.ZipFile(temp_jasp_file.name, 'r') as z:
                # Iterate through all JSON files in the archive to find the analysis
                # JASP stores analyses in nested structures inside JSONs
                full_json_str = ""
                for name in z.namelist():
                    if name.endswith('.json'):
                        try:
                            content = z.read(name).decode('utf-8', errors='ignore')
                            full_json_str += content + "\n"
                        except:
                            pass
                
                full_lower = full_json_str.lower()
                
                # Check Analysis Type
                if "ttestbayesianonesample" in full_lower.replace(" ", "") or \
                   ("bayesian" in full_lower and "onesample" in full_lower.replace(" ", "")):
                    score += 15
                    analysis_correct = True
                    feedback_parts.append("Correct Analysis Type (Bayesian One-Sample)")
                else:
                    feedback_parts.append("Incorrect Analysis Type")

                # Check Variable
                if '"exam"' in full_lower:
                    score += 15
                    variable_correct = True
                    feedback_parts.append("Correct Variable (Exam)")
                else:
                    feedback_parts.append("Variable 'Exam' not found in analysis")

                # Check Test Value (50)
                # Look for patterns like "testValue": 50 or value: 50 in context
                if '"testvalue": 50' in full_lower.replace(" ", "") or \
                   '"testvalue":50' in full_lower.replace(" ", "") or \
                   'value:50' in full_lower.replace(" ", ""):
                    score += 15
                    test_value_correct = True
                    feedback_parts.append("Correct Test Value (50)")
                elif "50" in full_lower:
                    # Softer check if strict JSON parsing fails due to structure
                    score += 10
                    test_value_correct = True
                    feedback_parts.append("Test Value 50 found (implicit)")
                else:
                    feedback_parts.append("Test Value 50 not found")

                # Check Bayes Factor Result
                # We expect BF10 > 1. Look for BF10 value in the output.
                # Regex for "BF10" followed by a number
                bf_matches = re.findall(r'bf10["\s:]+([0-9]+\.?[0-9]*)', full_lower)
                bf_valid = False
                for val in bf_matches:
                    try:
                        fval = float(val)
                        if 1.0 < fval < 1000.0:
                            bf_valid = True
                            break
                    except:
                        pass
                
                if bf_valid:
                    score += 15
                    bf_correct = True
                    feedback_parts.append("BF₁₀ indicates evidence for H₁")
                else:
                    feedback_parts.append("BF₁₀ value not found or out of expected range")

                # Check Settings (Descriptives, Plots)
                settings_score = 0
                if "descriptives" in full_lower:
                    settings_score += 3
                if "priorandposterior" in full_lower.replace(" ", "") or "prior" in full_lower:
                    settings_score += 4
                if "robustness" in full_lower:
                    settings_score += 3
                
                if settings_score > 0:
                    score += settings_score
                    settings_correct = True
                    feedback_parts.append(f"Settings/Plots partial match ({settings_score}/10)")

    except Exception as e:
        feedback_parts.append(f"Error parsing JASP file: {str(e)}")
    finally:
        if os.path.exists(temp_jasp_file.name):
            os.unlink(temp_jasp_file.name)

    # ------------------------------------------------------------------
    # Step 3: VLM Verification (Trajectory)
    # ------------------------------------------------------------------
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames:
        vlm_images = frames + ([final_screen] if final_screen else [])
        prompt = """
        You are verifying a user using JASP statistical software.
        The user should have:
        1. Opened the 'Bayesian One Sample T-Test' analysis.
        2. Selected the variable 'Exam'.
        3. Set the Test Value to 50.
        4. Enabled 'Descriptives', 'Prior and posterior' plot, and 'Robustness check' plot.
        
        Look at the screenshots. Can you confirm any of these actions?
        Return a JSON object with boolean keys: 'analysis_opened', 'variable_selected', 'test_value_set', 'plots_visible'.
        """
        
        try:
            result = query_vlm(images=vlm_images, prompt=prompt)
            parsed = result.get('parsed', {})
            
            vlm_score = 0
            if parsed.get('analysis_opened'): vlm_score += 2
            if parsed.get('variable_selected'): vlm_score += 2
            if parsed.get('test_value_set'): vlm_score += 3
            if parsed.get('plots_visible'): vlm_score += 3
            
            score += vlm_score
            feedback_parts.append(f"VLM verified workflow ({vlm_score}/10)")
        except Exception as e:
            logger.warning(f"VLM query failed: {e}")
            # Fallback: give partial credit if file was correct
            if analysis_correct and variable_correct:
                score += 10
                feedback_parts.append("VLM skipped, credited based on file evidence")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    passed = score >= 60 and analysis_correct and variable_correct
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }