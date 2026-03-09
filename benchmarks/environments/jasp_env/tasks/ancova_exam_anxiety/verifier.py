#!/usr/bin/env python3
"""
Verifier for ANCOVA Exam Anxiety Task.
Verifies that the agent performed an ANCOVA in JASP and produced a report with correct statistics.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ancova_exam_anxiety(traj, env_info, task_info):
    """
    Verifies the ANCOVA task execution.
    
    Criteria:
    1. JASP analysis file (.jasp) created and valid (30 pts)
    2. Text report created (10 pts)
    3. Report content analysis (60 pts total):
       - Anxiety covariate statistics (F, p)
       - Gender effect statistics (F, p)
       - Adjusted marginal means
       - Homogeneity assumption check
    """
    
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Check 1: JASP File (30 pts) ---
    jasp_info = result.get("jasp_file", {})
    if jasp_info.get("exists"):
        if jasp_info.get("valid_zip"):
            if jasp_info.get("created_during_task"):
                score += 30
                feedback.append("Valid JASP analysis file created.")
            else:
                score += 10
                feedback.append("JASP file exists but was not modified during task.")
        else:
            score += 5
            feedback.append("JASP file exists but is not a valid zip archive.")
    else:
        feedback.append("JASP analysis file not found.")

    # --- Check 2: Report Existence (10 pts) ---
    report_info = result.get("report_file", {})
    content = report_info.get("content", "")
    
    if report_info.get("exists") and len(content.strip()) > 50:
        score += 10
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing or empty.")
        # If report is missing, they can't get points for content
        return {
            "passed": False,
            "score": score,
            "feedback": " ".join(feedback)
        }

    # --- Check 3: Report Content Analysis (60 pts) ---
    # We look for numbers associated with keywords. 
    # This is a heuristic since we can't easily run a JASP file headless to check strict values.
    
    content_lower = content.lower()
    
    # A. Anxiety Covariate (15 pts)
    # Looking for "Anxiety" and "F" near each other, or p-value
    if "anxiety" in content_lower:
        if re.search(r"f\s*[=:]?\s*\d+\.\d+", content_lower) or re.search(r"p\s*[=:<>]?\s*0?\.\d+", content_lower):
            score += 15
            feedback.append("Report contains Anxiety statistics.")
        else:
            score += 5
            feedback.append("Report mentions Anxiety but lacks statistics.")
    else:
        feedback.append("Report does not mention Anxiety.")

    # B. Gender Main Effect (15 pts)
    if "gender" in content_lower:
        if re.search(r"f\s*[=:]?\s*\d+\.\d+", content_lower):
            score += 15
            feedback.append("Report contains Gender statistics.")
        else:
            score += 5
            feedback.append("Report mentions Gender but lacks F-statistics.")
    else:
        feedback.append("Report does not mention Gender.")

    # C. Marginal Means (10 pts)
    # Looking for mentions of "mean" and numbers that look like exam scores (0-100)
    means_found = re.findall(r"\b(mean|m)\b.*?(\d{1,2}\.\d+)", content_lower)
    valid_means = [m for m in means_found if 10.0 < float(m[1]) < 90.0] # Plausible exam scores
    
    if valid_means:
        score += 10
        feedback.append("Report contains plausible marginal means.")
    elif "mean" in content_lower:
        score += 5
        feedback.append("Report mentions means but values couldn't be parsed/validated.")

    # D. Effect Size (10 pts)
    # Looking for eta, η, or "effect size"
    if any(x in content_lower for x in ["eta", "η", "effect size"]):
        score += 10
        feedback.append("Report includes effect size.")
    else:
        feedback.append("Report missing effect size.")

    # E. Assumption Check (10 pts)
    # Homogeneity of regression slopes involves an interaction term
    if any(x in content_lower for x in ["homogeneity", "slope", "interaction", "assumption"]):
        score += 10
        feedback.append("Report mentions assumption checks (homogeneity/slopes).")
    else:
        feedback.append("Report missing homogeneity assumption check.")

    # Final Verification
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }