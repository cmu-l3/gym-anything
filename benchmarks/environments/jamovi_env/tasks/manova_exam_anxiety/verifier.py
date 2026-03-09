#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manova_exam_anxiety(traj, env_info, task_info):
    """
    Verify the MANOVA task by checking the reported values against ground truth
    and using VLM to verify the workflow trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch Task Results
    # ---------------------
    result_data = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}

    # 2. Fetch Ground Truth
    # ---------------------
    ground_truth = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            gt_path = result_data.get("ground_truth_path", "/var/lib/jamovi_ground_truth/manova_expected.json")
            copy_from_env(gt_path, f.name)
            f.seek(0)
            ground_truth = json.load(f)
        except Exception as e:
            logger.error(f"Failed to retrieve ground truth: {e}")
            # Fallback values if file missing (based on Field 2013 data)
            ground_truth = {
                "pillai_trace": 0.096, 
                "multivariate_F": 3.48, 
                "multivariate_p": 0.017,
                "univariate": {
                    "Exam": {"F": 16.96, "p": 0.000}, # Approx
                    "Anxiety": {"F": 0.00, "p": 1.0}, # Approx
                    "Revise": {"F": 0.00, "p": 1.0}   # Approx
                }
            }

    # 3. Scoring Criteria
    # -------------------
    score = 0
    feedback = []
    
    report_content = result_data.get("report_content", "")
    
    # Check 1: Files Exist (10 pts)
    if result_data.get("report_exists") and result_data.get("report_created_during_task"):
        score += 5
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing or not created during task.")

    if result_data.get("omv_exists") and result_data.get("omv_size_bytes", 0) > 1000:
        score += 5
        feedback.append("Jamovi project file saved.")
    else:
        feedback.append("Jamovi project file missing.")

    # Check 2: Multivariate Results (Pillai's Trace) (25 pts)
    # We look for numbers near the expected Pillai trace
    expected_pillai = ground_truth.get("pillai_trace", 0.0)
    
    # Regex to find Pillai value in text
    # Matches patterns like "Pillai's Trace: 0.096" or "0.096" in the Multivariate section
    pillai_matches = re.findall(r"0\.\d+", report_content)
    
    pillai_found = False
    for val_str in pillai_matches:
        try:
            val = float(val_str)
            if abs(val - expected_pillai) < 0.02:
                pillai_found = True
                break
        except:
            pass
            
    if pillai_found:
        score += 25
        feedback.append(f"Correct Pillai's Trace found (approx {expected_pillai:.3f}).")
    else:
        feedback.append(f"Pillai's Trace incorrect or not found in report (Expected ~{expected_pillai:.3f}).")

    # Check 3: Univariate Results (30 pts - 10 per variable)
    uni_gt = ground_truth.get("univariate", {})
    
    # Helper to check univariate F stats in the text
    # We look for the F-value associated with variable names
    content_lower = report_content.lower()
    
    for dv in ["Exam", "Anxiety", "Revise"]:
        dv_data = uni_gt.get(dv, {})
        expected_f = dv_data.get("F", 0.0)
        expected_p = dv_data.get("p", 1.0)
        
        # Simple heuristic: Look for the variable name and the F value nearby
        # or just look for the F value in the text if it's unique enough.
        # Given the unstructured nature of the requested text file, strict parsing is hard.
        # We search for the F-value within a reasonable tolerance.
        
        f_val_matches = re.findall(r"\d+\.\d+", report_content)
        f_found = False
        for val_str in f_val_matches:
            try:
                val = float(val_str)
                if abs(val - expected_f) < 0.5: # Loose tolerance for F
                    f_found = True
                    break
            except:
                pass
        
        if f_found and dv.lower() in content_lower:
            score += 10
            feedback.append(f"Univariate statistics for {dv} found.")
        else:
            feedback.append(f"Could not verify univariate stats for {dv} (Expected F~{expected_f:.2f}).")

    # Check 4: Box's M Mentioned (10 pts)
    if "box" in content_lower or "homogeneity" in content_lower:
        score += 10
        feedback.append("Box's M test reported.")
    else:
        feedback.append("Box's M test not found in report.")

    # Check 5: VLM Trajectory Verification (25 pts)
    # ---------------------------------------------
    # Use trajectory frames to confirm MANOVA setup
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user working in Jamovi.
    I need to verify if they performed a MANOVA analysis.
    
    Look for:
    1. The 'MANOVA' analysis panel open (or 'One-Way MANOVA').
    2. The variables 'Exam', 'Anxiety', and 'Revise' assigned as Dependent Variables.
    3. The variable 'Gender' assigned as the Grouping Variable/Factor.
    4. Output tables showing 'Multivariate Tests' (Pillai's Trace) and 'Univariate Tests'.
    
    Did the user perform this specific MANOVA analysis configuration?
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result.get("success"):
        # Simple keyword check on VLM reasoning if structured parsing fails
        response = vlm_result.get("result", "").lower()
        if "yes" in response or "performed" in response:
            vlm_score = 25
            feedback.append("VLM verified MANOVA workflow.")
        elif "partially" in response:
            vlm_score = 15
            feedback.append("VLM partially verified workflow.")
        else:
            feedback.append(f"VLM did not verify workflow: {response[:50]}...")
    else:
        # Fallback if VLM fails: check if app was running and report has content
        if result_data.get("app_running") and len(report_content) > 50:
            vlm_score = 10
            feedback.append("VLM failed, fallback points for app running.")
            
    score += vlm_score

    # Final result
    passed = score >= 60 and pillai_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "ground_truth": ground_truth,
            "reported_content_sample": report_content[:100]
        }
    }