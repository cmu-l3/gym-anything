#!/usr/bin/env python3
"""
Verifier for knowledge_base_extraction task.

Scoring Criteria (100 pts total):
1. Folders Created (24 pts): 8 pts each for KB-Security, KB-Linux, KB-Development.
2. Folders Populated (26 pts): 
   - 16 pts for minimum population (>=3 emails in each).
   - 10 pts for good volume (>=15 emails total across KB folders).
3. Index File (25 pts):
   - 8 pts for existence.
   - 12 pts for correct content structure (categories detected).
   - 5 pts for count accuracy (matches actual folder counts).
4. Announcement Email (25 pts):
   - 15 pts for draft/sent to correct recipient.
   - 10 pts for correct subject/content quality.

Pass Threshold: 65 points.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_knowledge_base_extraction(traj, env_info, task_info):
    """Verify the Knowledge Base Extraction task."""
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Data extraction from result
    kb_folders = result.get("kb_folders", {})
    index_file = result.get("index_file", {})
    announcement = result.get("announcement_email", {})
    
    # --- Criterion 1: Folders Created (24 pts) ---
    required_folders = ["security", "linux", "development"]
    folders_found = []
    
    for req in required_folders:
        # Check if any created folder contains the required keyword
        match = next((f for f in kb_folders.keys() if req in f.lower()), None)
        if match:
            score += 8
            folders_found.append(req)
        else:
            feedback_parts.append(f"Missing folder: KB-{req.capitalize()}")

    if len(folders_found) == 3:
        feedback_parts.append("All 3 KB folders created")

    # --- Criterion 2: Folders Populated (26 pts) ---
    total_kb_emails = sum(kb_folders.values())
    min_threshold_met = 0
    
    # Check minimum per folder (>= 3)
    # We map found folders back to their counts
    for folder_name, count in kb_folders.items():
        if count >= 3:
            min_threshold_met += 1
    
    # 16 pts for minimum population coverage
    if min_threshold_met >= 3:
        score += 16
        feedback_parts.append("All folders minimally populated")
    elif min_threshold_met == 2:
        score += 8
        feedback_parts.append("2/3 folders minimally populated")
    elif min_threshold_met == 1:
        score += 4
        feedback_parts.append("1/3 folders minimally populated")
        
    # 10 pts for total volume (>= 15)
    if total_kb_emails >= 15:
        score += 10
        feedback_parts.append(f"Good email volume: {total_kb_emails} archived")
    elif total_kb_emails >= 10:
        score += 5
        feedback_parts.append(f"Moderate email volume: {total_kb_emails} archived")
    else:
        feedback_parts.append(f"Low archive volume: {total_kb_emails} (target 15+)")

    # --- Criterion 3: Index File (25 pts) ---
    if index_file.get("exists") and index_file.get("valid_timestamp"):
        score += 8
        feedback_parts.append("Index file created")
        
        content = index_file.get("content", "").lower()
        
        # Check structure (categories mentioned)
        cats_in_index = 0
        for req in required_folders:
            if req in content:
                cats_in_index += 1
        
        if cats_in_index == 3:
            score += 12
            feedback_parts.append("Index lists all categories")
        elif cats_in_index > 0:
            score += 4 * cats_in_index
            feedback_parts.append(f"Index lists {cats_in_index}/3 categories")
            
        # Check total count accuracy
        # Find numbers in the text and see if one matches total_kb_emails (+/- 2)
        numbers = [int(n) for n in re.findall(r'\b\d+\b', content)]
        match_total = any(abs(n - total_kb_emails) <= 2 for n in numbers)
        
        if match_total:
            score += 5
            feedback_parts.append("Index file count accuracy verified")
            
    else:
        feedback_parts.append("Index file missing or old")

    # --- Criterion 4: Announcement Email (25 pts) ---
    if announcement.get("found") and announcement.get("recipient_match"):
        score += 15
        feedback_parts.append("Announcement email drafted to IT Team")
        
        # Content quality
        subj_match = announcement.get("subject_match")
        body_has_count = bool(re.search(r'\d+', announcement.get("body_snippet", "")))
        
        if subj_match and body_has_count:
            score += 10
            feedback_parts.append("Announcement content valid")
        elif subj_match or body_has_count:
            score += 5
            feedback_parts.append("Announcement content partial match")
    else:
        feedback_parts.append("Announcement email not found")

    # --- Final Score Calculation ---
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }