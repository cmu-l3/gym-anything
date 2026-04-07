#!/usr/bin/env python3
"""
Verifier for upload_student_document task.
Verifies that the agent successfully uploaded a PDF file to a student record.
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities from the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_upload_student_document(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify upload student document task.
    
    Scoring:
    - 40 pts: File found on server in valid directory
    - 15 pts: File timestamp > task start time (Anti-gaming)
    - 15 pts: File size > 0 (Valid upload)
    - 30 pts: VLM Verification (Visual confirmation of UI state/workflow)
    """
    
    # 1. Setup copy from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env not available"}

    # 2. Read programmatic result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 3. Programmatic Checks (70 points total)
    file_found = result_data.get("file_found", False)
    is_new = result_data.get("is_new_file", False)
    file_size = result_data.get("found_file_size", 0)
    
    if file_found:
        score += 40
        feedback.append("Success: Uploaded file found on server.")
        
        if is_new:
            score += 15
            feedback.append("Verification: File was uploaded during this session.")
        else:
            feedback.append("Warning: File timestamp indicates it might be old.")
            
        if file_size > 100:  # Dummy PDF is ~300 bytes
            score += 15
            feedback.append(f"Verification: Valid file size ({file_size} bytes).")
        else:
            feedback.append("Warning: File seems empty.")
    else:
        feedback.append("Failed: No uploaded file found in OpenSIS directories.")

    # 4. VLM Verification (30 points total)
    # Use trajectory to confirm workflow if file check fails or to augment score
    vlm_score = 0
    
    prompt = """
    Analyze these screenshots of an agent using OpenSIS (Student Information System).
    Goal: Upload a file named 'transcript_source.pdf' to a student's record.
    
    Check for:
    1. Is the 'Files' or 'Documents' tab selected in a student profile?
    2. Is there a file list showing 'transcript_source.pdf'?
    3. Did a file upload dialog or file picker appear?
    
    Return JSON:
    {
        "student_profile_visible": boolean,
        "files_tab_active": boolean,
        "filename_visible": boolean,
        "upload_dialog_seen": boolean
    }
    """
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
        
    if frames:
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        
        if vlm_resp.get("success"):
            analysis = vlm_resp.get("parsed", {})
            
            # Points breakdown
            if analysis.get("student_profile_visible") or analysis.get("files_tab_active"):
                vlm_score += 10
            if analysis.get("upload_dialog_seen"):
                vlm_score += 10
            if analysis.get("filename_visible"):
                vlm_score += 10
                feedback.append("VLM: Confirmed 'transcript_source.pdf' is visible in the UI.")
        else:
            feedback.append("VLM check failed (technical error).")
    
    score += vlm_score

    # Final Pass Logic
    # Must have either the physical file (strongest proof) OR very strong VLM evidence
    passed = (file_found and is_new) or (vlm_score >= 25)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }