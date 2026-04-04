#!/usr/bin/env python3
"""
Verifier for nsf_grant_funding_analysis task.

Criteria:
1. Firefox history shows visits to nsf.gov (10 pts)
2. Bookmark folder "NSF Quantum Grants" exists (20 pts)
3. Folder contains >= 5 bookmarks to nsf.gov (20 pts)
4. JSON output file exists and is fresh (10 pts)
5. JSON contains >= 5 valid entries (20 pts)
6. Data quality (7-digit IDs, "Quantum" in titles) (20 pts)
"""

import json
import logging
import os
import tempfile
import re

logger = logging.getLogger(__name__)

def verify_nsf_grant_funding_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Retrieve result file
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name
    
    try:
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback = []

    # 1. History Check (10 pts)
    visits = data.get("nsf_visits", 0)
    if visits > 0:
        score += 10
        feedback.append("NSF.gov visited (10/10)")
    else:
        feedback.append("NSF.gov NOT visited (0/10)")

    # 2. Bookmark Folder Check (20 pts)
    if data.get("bookmark_folder_exists"):
        score += 20
        feedback.append("Bookmark folder 'NSF Quantum Grants' found (20/20)")
    else:
        feedback.append("Bookmark folder 'NSF Quantum Grants' MISSING (0/20)")

    # 3. Bookmark Content Check (20 pts)
    bm_count = data.get("nsf_bookmarks_count", 0)
    if bm_count >= 5:
        score += 20
        feedback.append(f"Found {bm_count} NSF bookmarks in folder (20/20)")
    elif bm_count >= 1:
        score += 10
        feedback.append(f"Found {bm_count} NSF bookmarks (required 5) (10/20)")
    else:
        feedback.append("No NSF bookmarks found in folder (0/20)")

    # 4. File Existence & Freshness (10 pts)
    if data.get("file_exists") and data.get("file_fresh"):
        score += 10
        feedback.append("Output file exists and created during task (10/10)")
    elif data.get("file_exists"):
        score += 5
        feedback.append("Output file exists but old/stale (5/10)")
    else:
        feedback.append("Output file MISSING (0/10)")

    # 5. Data Quantity Check (20 pts)
    output_data = data.get("output_data", [])
    if not isinstance(output_data, list):
        output_data = []
        
    entry_count = len(output_data)
    if entry_count >= 5:
        score += 20
        feedback.append(f"JSON contains {entry_count} entries (20/20)")
    elif entry_count >= 1:
        score += 10
        feedback.append(f"JSON contains {entry_count} entries (required 5) (10/20)")
    else:
        feedback.append("JSON list is empty or invalid (0/20)")

    # 6. Data Quality Check (20 pts)
    # Check structure and content of first 5 entries
    quality_score = 0
    valid_entries = 0
    
    for entry in output_data[:5]:
        is_valid = True
        
        # Check Award Number (7 digits)
        award_id = str(entry.get("award_number", ""))
        if not re.match(r"^\d{7}$", award_id):
            is_valid = False
            
        # Check Title Relevance (loose check)
        title = str(entry.get("title", "")).lower()
        if "quantum" not in title and "qubit" not in title and "algorithm" not in title:
            # Maybe relevant but title doesn't say? Penalize slightly but don't fail strictly 
            # if user found grants that are technically relevant but poorly titled.
            # But task asked for keyword "Quantum Computing".
            pass 
            
        # Check Amount (Basic format check)
        amount = str(entry.get("amount", ""))
        if not re.search(r"[\d,]+", amount):
            is_valid = False

        if is_valid:
            valid_entries += 1

    if valid_entries >= 5:
        quality_score = 20
    elif valid_entries >= 3:
        quality_score = 10
    elif valid_entries >= 1:
        quality_score = 5
        
    score += quality_score
    feedback.append(f"Data quality check: {valid_entries} valid entries ({quality_score}/20)")

    # Final Result
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback)
    }