#!/usr/bin/env python3
"""
Verifier for grants_gov_search task.

Criteria:
1. History: Visited grants.gov (10 pts)
2. Bookmarks: Folder 'Grant Prospects' created (15 pts)
3. Bookmarks: Contains ≥3 valid grants.gov links (15 pts)
4. File: grant_prospects.json exists and is fresh (10 pts)
5. JSON Structure: Valid list with correct keys (10 pts)
6. Data Validity: ≥3 items, real agency names, valid dates (40 pts)
"""

import json
import os
import tempfile
import logging
import re
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_grants_gov_search(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 2. Retrieve files
    # Get metadata/state result
    result_path = "/tmp/task_result.json"
    local_result_path = tempfile.mktemp()
    
    # Get user output file
    user_file_path = "/home/ga/Documents/grant_prospects.json"
    local_user_file_path = tempfile.mktemp()
    
    try:
        copy_from_env(result_path, local_result_path)
    except:
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task state result"}

    try:
        copy_from_env(user_file_path, local_user_file_path)
        user_file_retrieved = True
    except:
        user_file_retrieved = False

    # 3. Load Data
    try:
        with open(local_result_path, 'r') as f:
            state = json.load(f)
    except:
        return {"passed": False, "score": 0, "feedback": "Corrupt task result file"}

    score = 0
    feedback = []

    # 4. Evaluate Browser State (40 pts total)
    
    # Criterion 1: History (10 pts)
    visits = state.get("grants_gov_visits", 0)
    if visits > 0:
        score += 10
        feedback.append("History: Visited Grants.gov (10/10)")
    else:
        feedback.append("History: No evidence of visiting Grants.gov (0/10)")

    # Criterion 2: Bookmark Folder (15 pts)
    if state.get("bookmark_folder_exists", 0) == 1:
        score += 15
        feedback.append("Bookmarks: 'Grant Prospects' folder exists (15/15)")
    else:
        feedback.append("Bookmarks: 'Grant Prospects' folder missing (0/15)")

    # Criterion 3: Valid Bookmarks (15 pts)
    valid_bms = state.get("valid_bookmarks_count", 0)
    if valid_bms >= 3:
        score += 15
        feedback.append(f"Bookmarks: Found {valid_bms} valid links (15/15)")
    elif valid_bms > 0:
        partial = valid_bms * 5
        score += partial
        feedback.append(f"Bookmarks: Found only {valid_bms} valid links ({partial}/15)")
    else:
        feedback.append("Bookmarks: No valid grants.gov links found (0/15)")

    # 5. Evaluate Output File (60 pts total)

    # Criterion 4: File Existence (10 pts)
    if state.get("output_file_exists", False) and state.get("output_file_fresh", False):
        score += 10
        feedback.append("File: JSON output exists and is fresh (10/10)")
    else:
        feedback.append("File: JSON output missing or stale (0/10)")
        # Critical failure for subsequent checks
        return cleanup_and_return(score, feedback, local_result_path, local_user_file_path)

    # Load User JSON
    if not user_file_retrieved:
        feedback.append("File: Could not retrieve output file for analysis")
        return cleanup_and_return(score, feedback, local_result_path, local_user_file_path)
        
    try:
        with open(local_user_file_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        feedback.append("File: Invalid JSON syntax (0/50)")
        return cleanup_and_return(score, feedback, local_result_path, local_user_file_path)

    # Criterion 5: Structure (10 pts)
    if not isinstance(data, list):
        feedback.append("Structure: Root element is not a list (0/10)")
    else:
        required_keys = {"opportunity_number", "title", "agency", "posted_date", "close_date"}
        structure_valid = True
        for item in data:
            if not isinstance(item, dict) or not required_keys.issubset(item.keys()):
                structure_valid = False
                break
        
        if structure_valid and len(data) > 0:
            score += 10
            feedback.append("Structure: Valid JSON schema (10/10)")
        else:
            feedback.append("Structure: Missing required keys in objects (0/10)")

    # Criterion 6: Data Content (40 pts)
    if isinstance(data, list):
        # Quantity
        if len(data) >= 3:
            score += 10
            feedback.append("Data: Sufficient entries (>=3) (10/10)")
        else:
            feedback.append(f"Data: Insufficient entries ({len(data)}/3) (0/10)")

        # Quality Check
        valid_entries = 0
        federal_keywords = ["Department", "Administration", "Service", "Bureau", "Agency", "Commission", "Institute"]
        
        for item in data:
            try:
                # Check Opportunity Number (basic format check)
                opp_num = str(item.get("opportunity_number", ""))
                title = str(item.get("title", ""))
                agency = str(item.get("agency", ""))
                
                # Agency heuristic
                agency_valid = any(kw in agency for kw in federal_keywords) or len(agency) > 3
                
                # Check not placeholder
                not_placeholder = "test" not in title.lower() and "example" not in title.lower()
                
                if len(opp_num) > 3 and agency_valid and not_placeholder:
                    valid_entries += 1
            except:
                pass
        
        if valid_entries >= 3:
            score += 30
            feedback.append("Data: Content appears valid and realistic (30/30)")
        elif valid_entries > 0:
            score += 15
            feedback.append("Data: Some content looks valid but not all (15/30)")
        else:
            feedback.append("Data: Content looks invalid or placeholder (0/30)")

    return cleanup_and_return(score, feedback, local_result_path, local_user_file_path)

def cleanup_and_return(score, feedback, f1, f2):
    if os.path.exists(f1): os.unlink(f1)
    if os.path.exists(f2): os.unlink(f2)
    
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }