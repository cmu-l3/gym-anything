#!/usr/bin/env python3
"""
Verifier for export_visitor_log task.

Verifies that:
1. An export file exists on the Desktop.
2. The file was created during the task window (anti-gaming).
3. The file contains expected data (specific visitor names).
4. VLM verifies the UI interaction (export dialogs).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_visitor_log(traj, env_info, task_info):
    """
    Verify the visitor log export task.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    # Note: verifier logic uses the counts calculated in export_result.sh
    # to avoid needing to parse complex file formats (xls/xml) inside python here,
    # relying on grep/text checks from the shell script for robustness.
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Read result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. File-Based Verification (75 points total)
    
    # A. File Existence (20 pts)
    if result.get('file_found', False):
        score += 20
        feedback_parts.append("Export file found on Desktop.")
    else:
        feedback_parts.append("No export file found on Desktop.")
        # Critical failure
        return {"passed": False, "score": 0, "feedback": "Failed: No export file found."}

    # B. Anti-Gaming / Timestamp (10 pts)
    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task session.")
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not created during this session.")

    # C. File Size & Content (15 pts)
    size = result.get('file_size_bytes', 0)
    lines = result.get('line_count', 0)
    
    if size > 100:
        score += 5
        feedback_parts.append("File size is valid.")
    
    if result.get('header_detected', False):
        score += 5
        feedback_parts.append("Header row detected.")
        
    if lines >= 6:
        score += 5
        feedback_parts.append(f"Contains {lines} rows (expected >= 6).")
    else:
        feedback_parts.append(f"File contains only {lines} rows.")

    # D. Data Validation (Specific Names) (30 pts)
    # 5 pts per name found, max 30
    names_found = result.get('names_found_count', 0)
    name_score = min(30, names_found * 5)
    score += name_score
    feedback_parts.append(f"Found {names_found} expected visitor names in file.")

    # 3. VLM Verification (25 points total)
    # We check if the agent actually used the UI to export, preventing
    # cases where they might just echo text to a file in a terminal.
    
    frames = sample_trajectory_frames(traj, n=6)
    vlm_prompt = """
    Analyze these screenshots of a user interacting with "Jolly Lobby Track" software.
    I need to verify if the user performed a data export operation.
    
    Look for:
    1. Navigation to a "Log", "Reports", or "Database" view.
    2. A "Save As", "Export", or "Print to File" dialog box.
    3. Selection of a file format (CSV, Text, Excel) or typing a filename.
    
    Did the user perform these actions?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        # Simple keyword matching in VLM reasoning or use structured output if available
        # Assuming bool/confidence return structure or parsing reasoning text
        reasoning = vlm_result.get('parsed', {}).get('reasoning', str(vlm_result))
        lower_reasoning = reasoning.lower()
        
        if "yes" in lower_reasoning or "export" in lower_reasoning or "save" in lower_reasoning:
             vlm_score = 25
             feedback_parts.append("VLM confirmed export workflow.")
        else:
             feedback_parts.append("VLM could not confirm export workflow from screenshots.")
    else:
        feedback_parts.append("VLM verification unavailable.")
        # Fallback: give partial credit if file is perfect
        if score >= 60: 
            vlm_score = 15
    
    score += vlm_score

    # 4. Final Verdict
    # Threshold: 60 points + File must be created during task
    passed = (score >= 60) and result.get('file_created_during_task', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }