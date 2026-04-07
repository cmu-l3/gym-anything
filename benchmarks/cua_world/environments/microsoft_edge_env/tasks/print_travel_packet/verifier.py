#!/usr/bin/env python3
"""
Verifier for Print Travel Packet task.

Scoring Criteria:
1. Files exist and are valid PDFs (15 pts each -> 45 total)
2. Files contain correct content (keywords) (10 pts each -> 30 total)
3. Files created after task start (Anti-gaming) (10 pts)
4. Browser history confirms Wikipedia visits (10 pts)
5. All three files present (Completion bonus) (5 pts)

Total: 100 points
Pass Threshold: 65 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_print_travel_packet(traj, env_info, task_info):
    """
    Verify the print_travel_packet task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    files = result.get("files", {})
    history = result.get("history", {}).get("wikipedia_visits", "")
    
    # 1. Verify Files (Existence, Format, Content)
    file_targets = [
        ("schengen", "Schengen Area", 15, 10),
        ("jet_lag", "Jet Lag", 15, 10),
        ("travel_doc", "Travel Documents", 15, 10)
    ]
    
    all_files_exist = True
    all_created_after = True
    
    for key, name, exist_pts, content_pts in file_targets:
        f_data = files.get(key, {})
        
        # Check Existence & Format
        if f_data.get("exists") and f_data.get("is_pdf") and f_data.get("size", 0) > 1000:
            score += exist_pts
            feedback_parts.append(f"{name}: Valid PDF found ({exist_pts} pts)")
            
            # Check Content
            if f_data.get("has_keyword"):
                score += content_pts
                feedback_parts.append(f"{name}: Content verified ({content_pts} pts)")
            else:
                feedback_parts.append(f"{name}: Content keyword missing")
            
            # Check Timestamp
            if not f_data.get("created_after_start"):
                all_created_after = False
                feedback_parts.append(f"{name}: Stale timestamp!")
        else:
            all_files_exist = False
            feedback_parts.append(f"{name}: Not found or invalid")

    # 2. Timestamp Check (Global)
    if all_created_after and score > 0:
        score += 10
        feedback_parts.append("All timestamps valid (+10 pts)")
    else:
        feedback_parts.append("Timestamp check failed or no files found")

    # 3. History Check
    # We look for url fragments in the comma-separated history string
    visits = 0
    if "Schengen_Area" in history: visits += 1
    if "Jet_lag" in history: visits += 1
    if "Travel_document" in history: visits += 1
    
    if visits >= 2:
        score += 10
        feedback_parts.append(f"Browser history confirms visits ({visits}/3) (+10 pts)")
    else:
        feedback_parts.append(f"Insufficient history evidence ({visits}/3)")

    # 4. Completion Bonus
    if all_files_exist:
        score += 5
        feedback_parts.append("All files present (+5 pts)")

    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }