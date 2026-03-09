#!/usr/bin/env python3
"""
Verifier for verify_flight_search_error_handling task.

Criteria:
1. Report file exists and was created during the task.
2. Report contains documentation of INVALID flight search (ZZ0000).
3. Report contains documentation of VALID flight search (AA100).
4. VLM verification: Trajectory shows search screen, error message, and valid flight details.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flight_search_error_handling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    valid_keywords = metadata.get('valid_keywords', ["American", "Dallas", "London", "DFW", "LHR"])

    score = 0
    feedback_parts = []
    
    # =======================================================
    # 1. File Verification (Programmatic) - 40 Points
    # =======================================================
    
    # Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check existence and timestamp
    if not result_data.get('report_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if not result_data.get('file_created_during_task', False):
        feedback_parts.append("Warning: File timestamp check failed (pre-existing or clock skew).")
        # We penalize but don't fail immediately if content is good
    else:
        score += 10
        feedback_parts.append("Report file created during task.")

    # Retrieve and Content Check the Report
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    report_content = ""
    try:
        copy_from_env(metadata['report_path'], temp_report.name)
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
    except Exception as e:
        feedback_parts.append(f"Failed to read report content: {str(e)}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # Content Analysis
    report_lower = report_content.lower()
    
    # Check Invalid Search Section
    if "zz0000" in report_lower and ("error" in report_lower or "found" in report_lower or "invalid" in report_lower):
        score += 15
        feedback_parts.append("Report documents invalid flight error.")
    else:
        feedback_parts.append("Report missing valid documentation of ZZ0000 error.")

    # Check Valid Search Section
    has_valid_flight = "aa100" in report_lower
    has_details = any(kw.lower() in report_lower for kw in valid_keywords)
    
    if has_valid_flight and has_details:
        score += 15
        feedback_parts.append("Report documents valid flight details.")
    elif has_valid_flight:
        score += 10
        feedback_parts.append("Report mentions AA100 but lacks detail.")
    else:
        feedback_parts.append("Report missing documentation of AA100.")

    # =======================================================
    # 2. VLM Trajectory Verification - 60 Points
    # =======================================================
    
    # Sample frames from the trajectory to catch transient states (error messages)
    frames = sample_trajectory_frames(traj, n=8)
    
    if not frames:
        feedback_parts.append("No video trajectory available for verification.")
    else:
        vlm_prompt = """
        You are verifying a software testing task on a mobile app flight tracker.
        
        The user was supposed to:
        1. Search for an INVALID flight 'ZZ0000' and trigger an error.
        2. Search for a VALID flight 'AA100' and see flight details (American Airlines, DFW-LHR).
        
        Look at the sequence of screenshots. Answer the following in JSON format:
        {
            "seen_search_screen": boolean,
            "seen_error_message": boolean,
            "seen_valid_flight_details": boolean,
            "description": "Short description of what happened"
        }
        
        "seen_error_message": True if you see red text, 'No flight found', 'Error', or a dialog box after a search.
        "seen_valid_flight_details": True if you see flight times, airline logo, or route info for AA100.
        """
        
        try:
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            parsed = vlm_result.get('parsed', {})
            
            if parsed.get('seen_search_screen'):
                score += 10
                feedback_parts.append("VLM: Search screen visited.")
                
            if parsed.get('seen_error_message'):
                score += 25
                feedback_parts.append("VLM: Error state successfully triggered/observed.")
            else:
                feedback_parts.append("VLM: Did not clearly see the error message.")
                
            if parsed.get('seen_valid_flight_details'):
                score += 25
                feedback_parts.append("VLM: Valid flight details successfully loaded.")
            else:
                feedback_parts.append("VLM: Did not clearly see valid flight details.")
                
        except Exception as e:
            feedback_parts.append(f"VLM analysis failed: {str(e)}")

    # =======================================================
    # Final Scoring
    # =======================================================
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }