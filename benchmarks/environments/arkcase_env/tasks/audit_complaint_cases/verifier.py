#!/usr/bin/env python3
"""
Verifier for audit_complaint_cases task.
Verifies that the agent created a text report containing specific details
(Case Number, Title, Priority) for 4 pre-created complaint cases.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_complaint_cases(traj, env_info, task_info):
    """
    Verify the audit report content against ground truth and check VLM trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Data
    # ----------------
    
    # Get task result metadata
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to copy task_result.json: {e}")

    # Get Ground Truth
    ground_truth = []
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/ground_truth_complaints.json", f.name)
            f.seek(0)
            ground_truth = json.load(f)
        except Exception as e:
            logger.error(f"Failed to copy ground truth: {e}")
            return {"passed": False, "score": 0, "feedback": "System error: could not load ground truth data"}

    # Get User Report
    report_content = ""
    report_exists = task_result.get("report_exists", False)
    
    if report_exists:
        with tempfile.NamedTemporaryFile(suffix='.txt') as f:
            try:
                copy_from_env("/home/ga/audit_report.txt", f.name)
                f.seek(0)
                report_content = f.read().decode('utf-8', errors='ignore')
            except Exception as e:
                logger.error(f"Failed to copy report: {e}")

    # 2. Score Report Content
    # -----------------------
    score = 0
    feedback_parts = []
    
    # Basic Checks (10 pts)
    if report_exists and len(report_content.strip()) > 10:
        score += 5
        feedback_parts.append("Report file exists")
    else:
        feedback_parts.append("Report file missing or empty")
        
    if task_result.get("file_created_during_task", False):
        score += 5
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp invalid (pre-existing?)")

    # Content Matching (15 pts per case = 60 pts)
    # We look for the Case Number in the text, then check if Title keywords and Priority are in the same line/block.
    
    cases_found = 0
    report_lines = report_content.lower().split('\n')
    
    for case in ground_truth:
        c_num = case.get("caseNumber", "UNKNOWN").lower()
        c_title = case.get("title", "").lower()
        c_prio = case.get("priority", "").lower()
        
        case_matched = False
        
        # Identify specific keywords from title to allow fuzzy matching
        # e.g., "Delayed Response" from "Delayed Response to Records Request"
        # We take the first 2 significant words
        title_keywords = [w for w in c_title.split() if len(w) > 3][:3]
        
        # Scan report for this case
        found_num = False
        found_title = False
        found_prio = False
        
        # Strategy: Look for the Case Number first (it's unique)
        # If found in a line, check that line for other details
        for line in report_lines:
            if c_num in line:
                found_num = True
                
                # Check priority in same line
                if c_prio in line:
                    found_prio = True
                
                # Check title keywords in same line
                matches = sum(1 for k in title_keywords if k in line)
                if matches >= 1: # At least one keyword matches
                    found_title = True
                break
        
        # Scoring for this case
        case_score = 0
        if found_num:
            case_score += 5
        if found_title:
            case_score += 5
        if found_prio:
            case_score += 5
            
        score += case_score
        
        if case_score == 15:
            cases_found += 1
            feedback_parts.append(f"Case {c_num}: Perfect match")
        elif case_score > 0:
            feedback_parts.append(f"Case {c_num}: Partial match ({case_score}pts)")
        else:
            feedback_parts.append(f"Case {c_num}: Not found")

    if cases_found == 4:
        score += 10 # Bonus for getting all perfectly
        feedback_parts.append("Bonus: All cases perfectly reported")

    # 3. VLM Trajectory Verification (20 pts)
    # ---------------------------------------
    # We want to verify they actually logged in and looked at the list
    
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    if frames:
        prompt = """
        Analyze this sequence of screenshots from a user performing an audit task in ArkCase.
        I need to verify three things:
        1. Did the user successfully log in to ArkCase? (Look for dashboard/menu)
        2. Did the user navigate to the 'Complaints' module? (Look for a list of items with 'Complaint' headers)
        3. Did the user view details of cases?
        
        Output JSON: {"logged_in": bool, "viewed_complaints": bool, "confidence": float}
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final], prompt=prompt).get('parsed', {})
            if vlm_res.get('logged_in'):
                vlm_score += 10
                feedback_parts.append("VLM: Login verified")
            if vlm_res.get('viewed_complaints'):
                vlm_score += 10
                feedback_parts.append("VLM: Complaints list access verified")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if report is perfect, assume they looked
            if cases_found >= 3:
                vlm_score = 20
    
    score += vlm_score

    # 4. Final Decision
    # -----------------
    # Threshold: Need report file + at least 3 cases reasonably identified + reasonable score
    passed = (task_result.get("file_created_during_task", False) and 
              score >= 60 and 
              cases_found >= 2) # At least 2 perfect cases or equivalent partials

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }