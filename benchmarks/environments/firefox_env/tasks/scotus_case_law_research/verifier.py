#!/usr/bin/env python3
"""
Verifier for SCOTUS Case Law Research Task
"""

import json
import logging
import os
import tempfile
import re

logger = logging.getLogger(__name__)

def normalize_citation(cit):
    """Normalize citation strings (e.g. '372 U.S. 335' -> '372us335')"""
    if not cit: return ""
    return re.sub(r'[\s\.]', '', str(cit).lower())

def normalize_author(auth):
    """Normalize author names (e.g. 'Justice Black' -> 'black')"""
    if not auth: return ""
    return str(auth).lower().replace("justice", "").strip()

def verify_scotus_case_law_research(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Get Metadata/Ground Truth
    metadata = task_info.get('metadata', {})
    gt = metadata.get('ground_truth', {})

    # 3. Fetch Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Scoring Variables
    score = 0
    feedback = []
    
    # --- Criterion A: Research Evidence (30 pts) ---
    
    # History Check (15 pts)
    if result.get('history_hits', 0) > 0:
        score += 15
        feedback.append("Browser history shows visits to legal databases (+15).")
    else:
        feedback.append("No history of visiting legal databases found (0/15).")

    # Bookmark Check (15 pts)
    folder_ok = result.get('bookmark_folder_exists', False)
    count = result.get('bookmark_count', 0)
    
    if folder_ok:
        if count >= 3:
            score += 15
            feedback.append(f"'Constitutional Law' folder found with {count} bookmarks (+15).")
        else:
            score += 5
            feedback.append(f"'Constitutional Law' folder found but only has {count}/3 bookmarks (+5).")
    else:
        feedback.append("'Constitutional Law' bookmark folder not found (0/15).")

    # --- Criterion B: Output File Basics (20 pts) ---
    
    file_exists = result.get('file_exists', False)
    file_fresh = result.get('file_fresh', False)
    content = result.get('file_content', {})

    if file_exists and file_fresh:
        score += 10
        feedback.append("Output file created during task (+10).")
    elif file_exists:
        score += 5
        feedback.append("Output file exists but timestamp is old (+5).")
    else:
        feedback.append("Output file not found (0/10).")
        # Critical failure for data checks if file missing
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # JSON Structure Check
    cases_present = [k for k in ['gideon', 'miranda', 'tinker'] if k in content]
    if len(cases_present) == 3:
        score += 10
        feedback.append("JSON structure contains all required cases (+10).")
    else:
        score += (len(cases_present) * 3)
        feedback.append(f"JSON structure missing cases. Found: {cases_present} (partial pts).")

    # --- Criterion C: Data Accuracy (50 pts) ---
    # Breakdown: Gideon(15), Miranda(15), Tinker(20)
    # Each case: Citation(5), Vote(5), Author(5/10)

    for case_key, case_points in [('gideon', 15), ('miranda', 15), ('tinker', 20)]:
        case_data = content.get(case_key, {})
        gt_data = gt.get(case_key, {})
        
        c_score = 0
        
        # Check Citation (approx 1/3 pts)
        if normalize_citation(case_data.get('citation')) == normalize_citation(gt_data.get('citation')):
            c_score += 5
        
        # Check Vote (approx 1/3 pts)
        # Handle '7-2' vs '7 to 2'
        vote_agent = str(case_data.get('vote_count', '')).strip()
        vote_gt = str(gt_data.get('vote_count', '')).strip()
        if vote_agent == vote_gt:
            c_score += 5
        
        # Check Author (approx 1/3 pts)
        # Tinker is weighted higher (20 total), so give 10 for author
        author_pts = 10 if case_key == 'tinker' else 5
        if normalize_author(gt_data.get('opinion_author')) in normalize_author(case_data.get('opinion_author')):
            c_score += author_pts
            
        score += c_score
        if c_score == case_points:
            feedback.append(f"{case_key.capitalize()} data correct (+{case_points}).")
        else:
            feedback.append(f"{case_key.capitalize()} data partial/incorrect ({c_score}/{case_points}).")

    # 5. Final Result
    passed = (score >= 70)
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }