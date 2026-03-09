#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_split_complaint(traj, env_info, task_info):
    """
    Verifies the split_multi_issue_complaint task.
    """
    # 1. Setup and load data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    original_case = result.get("original_case_data", {})
    search_results = result.get("search_results", [])
    associations = result.get("associations", [])
    notes = result.get("notes", [])
    
    # Metadata for validation
    metadata = task_info.get("metadata", {})
    sanitation_kws = metadata.get("sanitation_keywords", ["trash", "rat"])
    noise_kws = metadata.get("noise_keywords", ["drum", "loud"])

    score = 0
    feedback = []

    # --- CRITERION 1: Original Case Updated (20 pts) ---
    # Title should be "Noise Violation..."
    # Description should NOT have "trash" or "rats"
    orig_title = original_case.get("complaintTitle", "") or original_case.get("title", "")
    orig_desc = original_case.get("details", "") or original_case.get("description", "")
    
    c1_score = 0
    if "noise" in orig_title.lower():
        c1_score += 10
        feedback.append("Original case title updated correctly.")
    else:
        feedback.append(f"Original case title incorrect: '{orig_title}'")

    has_sanitation_text = any(kw in orig_desc.lower() for kw in sanitation_kws)
    has_noise_text = any(kw in orig_desc.lower() for kw in noise_kws)
    
    if has_noise_text and not has_sanitation_text:
        c1_score += 10
        feedback.append("Original case description cleaned correctly.")
    elif has_sanitation_text:
        feedback.append("Original case still contains sanitation details.")
    else:
        feedback.append("Original case description missing noise details.")
        
    score += c1_score

    # --- CRITERION 2: New Case Created (30 pts) ---
    # Look for a case with "Sanitation" in title and correct description
    new_case = None
    # search_results might be a dict (paged response) or list
    if isinstance(search_results, dict):
        search_list = search_results.get("results", []) or search_results.get("complaints", [])
    else:
        search_list = search_results

    for case in search_list:
        # Ignore the original case ID
        if str(case.get("id", "")) == str(result.get("original_case_id", "xxx")):
            continue
            
        c_title = case.get("complaintTitle", "") or case.get("title", "")
        c_desc = case.get("details", "") or case.get("description", "")
        
        if "sanitation" in c_title.lower() and any(kw in c_desc.lower() for kw in sanitation_kws):
            new_case = case
            break
            
    if new_case:
        score += 30
        feedback.append(f"New sanitation case found: {new_case.get('caseNumber', 'Unknown')}")
    else:
        feedback.append("New sanitation case NOT found in system.")

    # --- CRITERION 3: Cases Linked (30 pts) ---
    # Check associations of original case for the new case ID
    linked = False
    if new_case:
        new_id = str(new_case.get("id", ""))
        new_num = str(new_case.get("caseNumber", ""))
        
        # associations might be list of dicts
        for assoc in associations:
            # Check target ID or Case Number in association data
            assoc_str = json.dumps(assoc)
            if new_id in assoc_str or new_num in assoc_str:
                linked = True
                break
    
    if linked:
        score += 30
        feedback.append("Cases are successfully linked.")
    else:
        feedback.append("Link between cases not found.")

    # --- CRITERION 4: Cross-Reference Note (20 pts) ---
    note_found = False
    for note in notes:
        text = note.get("text", "") or note.get("note", "")
        if "split" in text.lower() or "new case" in text.lower():
            note_found = True
            break
            
    if note_found:
        score += 20
        feedback.append("Cross-reference note found.")
    else:
        feedback.append("No cross-reference note found on original case.")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }