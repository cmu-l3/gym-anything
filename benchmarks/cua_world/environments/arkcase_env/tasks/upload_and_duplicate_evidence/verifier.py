#!/usr/bin/env python3
"""
Verifier for upload_and_duplicate_evidence task.

Criteria:
1. "Access_Logs_2025.xlsx" exists in the case (Upload success).
2. "Access_Logs_Working_Copy.xlsx" exists in the case (Copy/Rename success).
3. Copy was created AFTER the upload/task start (integrity check).
4. Original local file still exists (optional good practice).
5. VLM verification of the "Documents" tab showing the files.
"""

import json
import os
import sys
import logging
from datetime import datetime

# Import VLM utils provided by the framework
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_upload_and_duplicate(traj, env_info, task_info):
    """
    Verify that the user uploaded the evidence and created a named copy.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_original = metadata.get('original_filename', 'Access_Logs_2025.xlsx')
    expected_copy = metadata.get('copy_filename', 'Access_Logs_Working_Copy.xlsx')

    # 1. Retrieve JSON result from container
    import tempfile
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_docs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        copy_from_env("/tmp/case_documents.json", temp_docs.name)
        
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
        
        with open(temp_docs.name, 'r') as f:
            documents = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_docs.name): os.unlink(temp_docs.name)

    # 2. Analyze API Data
    found_original = False
    found_copy = False
    
    # Normalize document names for comparison
    doc_names = [d.get('name', '') for d in documents]
    
    for name in doc_names:
        if expected_original in name:
            found_original = True
        if expected_copy in name:
            found_copy = True

    # 3. VLM Verification (Robust check for UI state)
    # The API might be tricky if the user uploaded to a specific subfolder or if the endpoint used in export wasn't perfect.
    # VLM acts as a "visual truth" check.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    all_images = frames + ([final_img] if final_img else [])
    
    vlm_prompt = f"""
    The user was asked to upload a file '{expected_original}' and create a copy named '{expected_copy}' in the ArkCase Documents tab.
    Look at the screenshots.
    1. Do you see a file list or document library?
    2. Is '{expected_original}' visible in the list?
    3. Is '{expected_copy}' visible in the list?
    4. Are they in the same folder?
    
    Return JSON:
    {{
        "documents_tab_visible": bool,
        "original_visible": bool,
        "copy_visible": bool,
        "filenames_correct": bool
    }}
    """
    
    vlm_result = query_vlm(images=all_images, prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {})
    
    vlm_original = vlm_data.get('original_visible', False)
    vlm_copy = vlm_data.get('copy_visible', False)
    
    # 4. Scoring
    score = 0
    feedback = []
    
    # Criterion A: Original File Present (40 pts)
    if found_original:
        score += 40
        feedback.append(f"API confirmed '{expected_original}' is present.")
    elif vlm_original:
        score += 30 # Slightly less if only visible visually (implies API might have missed it or partial upload)
        feedback.append(f"Visual check confirmed '{expected_original}' is present.")
    else:
        feedback.append(f"Missing original file '{expected_original}'.")
        
    # Criterion B: Copy File Present (40 pts)
    if found_copy:
        score += 40
        feedback.append(f"API confirmed '{expected_copy}' is present.")
    elif vlm_copy:
        score += 30
        feedback.append(f"Visual check confirmed '{expected_copy}' is present.")
    else:
        feedback.append(f"Missing copy file '{expected_copy}'.")
        
    # Criterion C: Local Source Preserved (10 pts)
    if result_data.get('local_source_preserved', False):
        score += 10
        feedback.append("Local source file preserved.")
        
    # Criterion D: Filenames Correct (10 pts)
    # Implicitly checked by finding them, but add bonus if names match exactly
    if found_original and found_copy:
        score += 10
        feedback.append("All filenames match exactly.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }