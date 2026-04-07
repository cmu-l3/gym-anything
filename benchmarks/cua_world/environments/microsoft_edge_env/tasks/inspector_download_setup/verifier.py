#!/usr/bin/env python3
"""
Verifier for Inspector Download Station Setup task.

Scoring Breakdown (100 points total):
1. Directory Structure (10 pts): InspectionDocs/{OSHA, FEMA, General} exist
2. Edge Settings (20 pts): 
   - Download dir set to InspectionDocs (15)
   - Prompt disabled (5)
3. Downloaded Content (35 pts):
   - Total valid PDFs >= 3 (15)
   - OSHA folder has PDF (10)
   - FEMA folder has PDF (10)
4. History Verification (15 pts):
   - Visited osha.gov (10)
   - Visited fema.gov (5)
5. Manifest (20 pts):
   - Exists & created after start (10)
   - Content mentions agencies (10)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/inspector_download_result.json"

def verify_inspector_download_setup(traj, env_info, task_info):
    """Verify the Inspector Download Station Setup task."""
    
    # 1. Setup access to result file
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task results: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Directory Structure (10 pts) ---
    struct = result.get("structure", {})
    if struct.get("root_exists") and struct.get("osha_dir") and struct.get("fema_dir") and struct.get("general_dir"):
        score += 10
        feedback.append("Directory structure correct (+10)")
    else:
        feedback.append(f"Directory structure incomplete: {struct}")

    # --- Criterion 2: Edge Settings (20 pts) ---
    prefs = result.get("preferences", {})
    target_dir = "/home/ga/Documents/InspectionDocs"
    
    # Check default directory
    current_dir = prefs.get("default_directory", "").rstrip('/')
    if current_dir == target_dir:
        score += 15
        feedback.append("Download directory configured correctly (+15)")
    else:
        feedback.append(f"Incorrect download directory: '{current_dir}' (expected '{target_dir}')")
        
    # Check prompt setting (should be false for automatic downloads)
    if prefs.get("prompt_for_download") is False:
        score += 5
        feedback.append("Download prompt disabled (+5)")
    else:
        feedback.append("Download prompt still enabled")

    # --- Criterion 3: Downloaded Content (35 pts) ---
    pdf_counts = result.get("pdf_counts", {})
    valid_pdfs = result.get("valid_new_pdfs", 0)
    
    # Quantity check
    if valid_pdfs >= 3:
        score += 15
        feedback.append(f"Downloaded {valid_pdfs} valid PDFs (+15)")
    elif valid_pdfs > 0:
        score += 5
        feedback.append(f"Only {valid_pdfs} valid PDFs downloaded (expected 3+) (+5)")
    else:
        feedback.append("No valid new PDFs found")

    # Organization check
    if pdf_counts.get("osha", 0) > 0:
        score += 10
        feedback.append("OSHA folder populated (+10)")
    else:
        feedback.append("OSHA folder empty")
        
    if pdf_counts.get("fema", 0) > 0:
        score += 10
        feedback.append("FEMA folder populated (+10)")
    else:
        feedback.append("FEMA folder empty")

    # --- Criterion 4: History Verification (15 pts) ---
    hist = result.get("history", {})
    if hist.get("osha"):
        score += 10
        feedback.append("Visited OSHA website (+10)")
    else:
        feedback.append("No history of visiting OSHA")
        
    if hist.get("fema"):
        score += 5
        feedback.append("Visited FEMA website (+5)")
    else:
        feedback.append("No history of visiting FEMA")

    # --- Criterion 5: Manifest (20 pts) ---
    manifest = result.get("manifest", {})
    if manifest.get("exists"):
        score += 10
        feedback.append("Manifest file created (+10)")
        
        if manifest.get("mentions_osha") and manifest.get("mentions_fema"):
            score += 10
            feedback.append("Manifest content valid (+10)")
        elif manifest.get("content_valid"):
            score += 5
            feedback.append("Manifest content partial (+5)")
        else:
            feedback.append("Manifest content empty or missing keywords")
    else:
        feedback.append("Manifest file missing")

    # --- Optional VLM Sanity Check ---
    # Only if score is high but verification seems borderline, or to confirm UI state
    # For this task, programmatic verification is very strong. 
    # We will use VLM just to ensure no "Error" dialogs are on screen in the final frame
    # which might indicate a crash despite files existing.
    
    # Passed Threshold
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }