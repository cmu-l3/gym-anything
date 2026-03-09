#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mediation_analysis(traj, env_info, task_info):
    """
    Verify the Mediation Analysis task.
    
    Scoring Breakdown (100 pts total):
    1. Output Files (30 pts):
       - .jasp project exists and modified (15 pts)
       - report.txt exists and modified (15 pts)
       
    2. Report Content (40 pts):
       - Mention of "Partial Mediation" (10 pts)
       - Path a (Anxiety->Revise) is negative (10 pts)
       - Indirect effect is negative (10 pts)
       - Total/Direct effects mentioned (10 pts)
       
    3. Visual Verification (30 pts):
       - VLM detects SEM/Mediation module in use (15 pts)
       - VLM confirms correct variables (Anxiety, Revise, Exam) used (15 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback = []
    
    # =========================================================
    # 1. File Verification (Programmatic)
    # =========================================================
    
    # Load JSON result
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results"}

    # Check JASP Project
    if task_result.get("project_exists") and task_result.get("project_modified"):
        if task_result.get("project_size", 0) > 2000: # Empty JASP files are small but usually >1KB
            score += 15
            feedback.append("JASP project file saved successfully.")
        else:
            feedback.append("JASP project file exists but seems too small.")
    else:
        feedback.append("JASP project file not found or not saved during task.")

    # Check Report File
    report_content = ""
    if task_result.get("report_exists") and task_result.get("report_modified"):
        score += 15
        feedback.append("Report text file created.")
        
        # Retrieve report content
        with tempfile.NamedTemporaryFile(suffix=".txt") as f:
            try:
                copy_from_env("/tmp/mediation_report.txt", f.name)
                f.seek(0)
                report_content = f.read().decode('utf-8', errors='ignore')
            except Exception as e:
                logger.error(f"Failed to read report: {e}")
    else:
        feedback.append("Report text file not found.")

    # =========================================================
    # 2. Content Verification (Regex/Parsing)
    # =========================================================
    
    if report_content:
        content_lower = report_content.lower()
        
        # Check Conclusion: "Partial Mediation"
        if "partial" in content_lower and "mediation" in content_lower:
            score += 10
            feedback.append("Correctly identified partial mediation.")
        elif "full" in content_lower and "mediation" in content_lower:
            feedback.append("Incorrect conclusion (Full Mediation).")
        elif "no" in content_lower and "mediation" in content_lower:
            feedback.append("Incorrect conclusion (No Mediation).")
        else:
            feedback.append("Mediation conclusion not found in report.")

        # Check Path A (Anxiety -> Revise) - Should be negative
        # Looking for patterns like "Path a: -0.7" or "Anxiety -> Revise: -0.71"
        # We look for a negative number contextually near "revise" or "path a"
        path_a_pattern = r"(path\s*a|anxiety.*revise|revise.*anxiety).*?(-\s*0\.\d+|-\s*[1-9])"
        if re.search(path_a_pattern, content_lower, re.DOTALL):
            score += 10
            feedback.append("Correctly reported negative coefficient for Path A (Anxiety->Revise).")
        else:
            feedback.append("Could not verify negative Path A coefficient in report.")

        # Check Indirect Effect - Should be negative
        indirect_pattern = r"(indirect).*?(-\s*0\.\d+|-\s*[1-9])"
        if re.search(indirect_pattern, content_lower, re.DOTALL):
            score += 10
            feedback.append("Correctly reported negative indirect effect.")
        else:
            feedback.append("Could not verify negative indirect effect in report.")

        # Check Direct/Total presence
        if "direct" in content_lower or "total" in content_lower:
            score += 10
            feedback.append("Reported Direct/Total effects.")
        else:
            feedback.append("Missing Direct or Total effect values.")

    # =========================================================
    # 3. Visual Verification (VLM)
    # =========================================================
    
    # We use trajectory frames to ensure they actually opened the module
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    Analyze these screenshots of the JASP statistical software.
    I am looking for evidence that the user performed a Mediation Analysis.
    
    Please check for:
    1. Is the "Mediation Analysis" or "SEM" (Structural Equation Modeling) module visible in the top bar or results panel?
    2. Is there a results table showing "Direct Effects", "Indirect Effects", or "Path Coefficients"?
    3. Are the variables "Anxiety", "Revise", and "Exam" visible in the variable selection boxes?
    
    Answer JSON: {"sem_module_visible": bool, "results_visible": bool, "variables_correct": bool}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    if vlm_data.get("sem_module_visible") or vlm_data.get("results_visible"):
        score += 15
        feedback.append("VLM confirmed Mediation/SEM analysis UI.")
    else:
        feedback.append("VLM did not see Mediation analysis interface.")
        
    if vlm_data.get("variables_correct"):
        score += 15
        feedback.append("VLM confirmed correct variables used.")
    else:
        feedback.append("VLM could not confirm variable selection.")

    # =========================================================
    # Final Scoring
    # =========================================================
    
    passed = score >= 60 and "Correctly identified partial mediation" in feedback
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }