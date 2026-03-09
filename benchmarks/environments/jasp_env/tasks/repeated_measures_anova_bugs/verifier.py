#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_values(report_text):
    """
    Extracts key statistical values from the student's report.
    Returns a dict with found F-values, p-values, means, etc.
    """
    values = {
        "f_values": [],
        "p_values": [],
        "etas": [],
        "means": [],
        "mauchly_mentioned": False
    }
    
    # Simple regex to find floating point numbers associated with keywords
    # This is heuristic; students format reports differently.
    
    # Check for Mauchly
    if re.search(r"mauchly|sphericity", report_text, re.IGNORECASE):
        values["mauchly_mentioned"] = True
        
    # Find all decimal numbers
    floats = re.findall(r"[-+]?\d*\.\d+|\d+", report_text)
    floats = [float(f) for f in floats if '.' in f] # Filter for likely stats
    
    # Store all found floats to check overlap with expected values
    values["all_floats"] = floats
    
    return values

def verify_repeated_measures_anova(traj, env_info, task_info):
    """
    Verifies the Repeated Measures ANOVA task.
    
    Criteria:
    1. JASP file created (10 pts)
    2. Report file created (10 pts)
    3. Files created *during* task (Anti-gaming) (10 pts)
    4. Report content accuracy (Matches Ground Truth Means) (25 pts)
    5. Report contains ANOVA stats (F, p, eta) (20 pts)
    6. VLM Verification of Workflow (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load Metadata & Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Load main result JSON
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        # Load Student Report
        report_text = ""
        if result_data.get("report_file_exists"):
            try:
                copy_from_env("/tmp/exported_report.txt", temp_report.name)
                with open(temp_report.name, 'r', errors='ignore') as f:
                    report_text = f.read()
            except Exception as e:
                logger.warning(f"Could not read report file: {e}")

        # Load Ground Truth
        ground_truth = {}
        try:
            copy_from_env("/tmp/exported_ground_truth.json", temp_gt.name)
            with open(temp_gt.name, 'r') as f:
                ground_truth = json.load(f)
        except Exception:
            logger.warning("Ground truth file missing")
            
    finally:
        for f in [temp_result, temp_report, temp_gt]:
            if os.path.exists(f.name):
                os.unlink(f.name)

    # 2. Score File Existence & Timestamps (30 pts)
    if result_data.get("jasp_file_exists"):
        score += 10
        feedback_parts.append("JASP file found.")
    else:
        feedback_parts.append("JASP file missing.")
        
    if result_data.get("report_file_exists"):
        score += 10
        feedback_parts.append("Report file found.")
    else:
        feedback_parts.append("Report file missing.")

    if result_data.get("jasp_file_created_during_task") and result_data.get("report_file_created_during_task"):
        score += 10
        feedback_parts.append("Files created during task session.")
    elif result_data.get("jasp_file_exists") or result_data.get("report_file_exists"):
        feedback_parts.append("Warning: Files detected but timestamps suggest they weren't created during this specific run.")

    # 3. Score Report Content (45 pts)
    content_score = 0
    if report_text:
        parsed = parse_report_values(report_text)
        
        # Check Means (25 pts)
        # We look for the ground truth mean values in the report text within a tolerance
        matched_means = 0
        total_means = len(ground_truth) # Should be 4
        
        for condition, mean_val in ground_truth.items():
            # Tolerance of 0.1
            found = False
            for num in parsed["all_floats"]:
                if abs(num - mean_val) < 0.1:
                    found = True
                    break
            if found:
                matched_means += 1
        
        if total_means > 0:
            mean_score = (matched_means / total_means) * 25
            content_score += mean_score
            feedback_parts.append(f"Reported Means Accuracy: {matched_means}/{total_means} correct.")

        # Check for ANOVA keywords/logic (20 pts)
        # Disgust effect should be huge (F > 100 usually). 
        # We just check if reasonable F-values (> 1.0) and p-values (< 1.0) are present.
        has_f = any(val > 1.0 for val in parsed["all_floats"])
        has_p = any(val < 1.0 for val in parsed["all_floats"])
        has_eta = "η" in report_text or "eta" in report_text.lower()
        
        if has_f and has_p:
            content_score += 10
            feedback_parts.append("Statistical values (F/p) detected.")
        if has_eta:
            content_score += 5
            feedback_parts.append("Effect size (eta) reported.")
        if parsed["mauchly_mentioned"]:
            content_score += 5
            feedback_parts.append("Sphericity/Mauchly mentioned.")
            
    score += content_score

    # 4. VLM Verification (25 pts)
    # Check if the UI shows the Repeated Measures ANOVA setup
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Review these screenshots of JASP software.
        1. Is the "Repeated Measures ANOVA" configuration panel visible? (It typically has boxes for 'Repeated Measures Factors' and 'Repeated Measures Cells').
        2. Are variables being dragged into the 'Repeated Measures Cells' box?
        3. Is there an output table visible showing ANOVA results?
        Answer with JSON: {"rm_anova_panel_visible": bool, "output_visible": bool}
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        vlm_data = vlm_res.get("parsed", {})
        
        vlm_score = 0
        if vlm_data.get("rm_anova_panel_visible"):
            vlm_score += 15
            feedback_parts.append("VLM confirmed RM ANOVA panel usage.")
        if vlm_data.get("output_visible"):
            vlm_score += 10
            feedback_parts.append("VLM confirmed results output.")
            
        score += vlm_score
    else:
        feedback_parts.append("No trajectory frames for VLM verification.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }