#!/usr/bin/env python3
"""
Verifier for batch_generate_schedules task.
Verifies that the agent generated a PDF containing specific Grade 9 students
and EXCLUDING Grade 10 students.
"""

import json
import os
import tempfile
import logging
import time
from pdfminer.high_level import extract_text

# Import VLM utils if available in environment, otherwise mock/skip
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    def sample_trajectory_frames(*args, **kwargs): return []
    def get_final_screenshot(*args, **kwargs): return None
    def query_vlm(*args, **kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_generate_schedules(traj, env_info, task_info):
    """
    Verify the batch schedule generation task.
    
    Criteria:
    1. A PDF file was created in Downloads (30 pts)
    2. File creation timestamp > task start time (10 pts)
    3. PDF content includes target students (Freshman One, Two, Three) (30 pts)
    4. PDF content EXCLUDES distractor student (Senior Student) (20 pts)
    5. VLM trajectory verification of UI workflow (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_students = metadata.get('target_students', ["Freshman One"])
    excluded_students = metadata.get('excluded_students', ["Senior Student"])

    feedback_parts = []
    score = 0
    
    # --- Step 1: Get Result JSON ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # --- Step 2: Check File Existence & Timestamp ---
    if not result_data.get('file_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No PDF file found in Downloads directory."
        }
    
    score += 30
    feedback_parts.append("PDF file found")
    
    task_start = result_data.get('task_start', 0)
    file_mtime = result_data.get('file_mtime', 0)
    
    if file_mtime > task_start:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("WARNING: File timestamp predates task start (stale file?)")
        # Continue verification but penalize
    
    # --- Step 3: Analyze PDF Content ---
    pdf_staged_path = result_data.get('pdf_staged_path')
    if not pdf_staged_path:
        return {"passed": False, "score": score, "feedback": "PDF path missing in result"}

    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    try:
        copy_from_env(pdf_staged_path, temp_pdf.name)
        
        # Extract text using pdfminer
        try:
            text_content = extract_text(temp_pdf.name)
            # Normalize whitespace
            text_content = " ".join(text_content.split())
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to parse PDF: {e}"}
            
        # Verify Inclusion Targets
        found_targets = 0
        for student in target_students:
            if student in text_content:
                found_targets += 1
            else:
                feedback_parts.append(f"Missing schedule for: {student}")
        
        # 10 points per target student (max 30)
        points_per_target = 30 // len(target_students) if target_students else 0
        score += (found_targets * points_per_target)
        if found_targets == len(target_students):
            feedback_parts.append("All target students found")
            
        # Verify Exclusion Targets
        excluded_found = 0
        for student in excluded_students:
            if student in text_content:
                excluded_found += 1
                feedback_parts.append(f"FAILED: Found excluded student: {student}")
        
        if excluded_found == 0:
            score += 20
            feedback_parts.append("Filtering correct (excluded students not found)")
            
    except Exception as e:
        feedback_parts.append(f"Error checking PDF content: {e}")
    finally:
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)

    # --- Step 4: VLM Trajectory Verification ---
    # We want to see if the agent actually used the UI to filter
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an agent's workflow in OpenSIS.
    The goal was to generate a 'Schedule Cards' report filtered for Grade 9 only.
    
    Look at the image sequence. Do you see:
    1. Navigation to Reports or Scheduling menu?
    2. A report configuration screen?
    3. Selection of 'Grade 9' or filtering criteria?
    4. Clicking a 'Generate' or 'Print' button?
    
    Return JSON: {"criteria_met": boolean, "confidence": "high/med/low"}
    """
    
    vlm_result = query_vlm(images=frames + ([final_screen] if final_screen else []), prompt=vlm_prompt)
    
    if vlm_result and isinstance(vlm_result, dict) and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("criteria_met", False):
            score += 10
            feedback_parts.append("VLM verified UI workflow")
    else:
        # Fallback if VLM fails or not available - assume OK if PDF is correct
        if score >= 60: 
            score += 10 # Grant benefit of doubt if output is perfect
            
    return {
        "passed": score >= 90, # Strict pass: Needs file + correct content + exclusion
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }