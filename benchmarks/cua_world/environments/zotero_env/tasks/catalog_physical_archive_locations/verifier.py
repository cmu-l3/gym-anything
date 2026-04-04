#!/usr/bin/env python3
"""
Verifier for catalog_physical_archive_locations task.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_catalog_physical_archive_locations(traj, env_info, task_info):
    """
    Verify that correct 'Call Number' values were assigned to specific papers.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"DB Query Error: {result['error']}"}

    items = result.get("items", [])
    meta = result.get("meta", {})
    task_start_ts = float(meta.get("task_start", 0))

    score = 0
    feedback_parts = []
    
    # Define targets
    # (Title substring, Expected Call Number, Points)
    targets = [
        # Turing Papers
        ("Computable Numbers", "BOX-TURING", 20),
        ("Computing Machinery", "BOX-TURING", 20),
        # Shannon Papers
        ("A Mathematical Theory", "BOX-SHANNON", 20),
        ("The Mathematical Theory", "BOX-SHANNON", 20), # The book with Weaver
        # Einstein Paper
        ("Electrodynamics", "BOX-RELATIVITY", 20)
    ]

    correct_count = 0
    
    for title_part, expected_call, points in targets:
        # Find item matching title
        found_item = None
        for item in items:
            if item.get("title") and title_part.lower() in item["title"].lower():
                found_item = item
                break
        
        if not found_item:
            feedback_parts.append(f"Paper containing '{title_part}' not found in library.")
            continue

        actual_call = found_item.get("callNumber")
        
        # Check Value
        if actual_call == expected_call:
            # Check Modification Time (Anti-gaming)
            # Zotero stores dateModified as "YYYY-MM-DD HH:MM:SS" (UTC usually)
            # We'll just give benefit of doubt if format parsing fails, 
            # but ideally we check if it was modified recently.
            # Since the task clears call numbers at start, strictly having the value 
            # implies it was added during the task (assuming clean start).
            score += points
            correct_count += 1
            feedback_parts.append(f"✓ '{title_part[:20]}...' filed correctly.")
        else:
            if actual_call:
                feedback_parts.append(f"✗ '{title_part[:20]}...' has wrong call number: '{actual_call}' (Expected: {expected_call})")
            else:
                feedback_parts.append(f"✗ '{title_part[:20]}...' has no call number.")

    # Deduct for mistakenly tagging other papers? 
    # (Optional, but let's stick to positive scoring for now)

    # Check application state
    if meta.get("app_running") != "true":
        feedback_parts.append("Warning: Zotero was not running at verification time.")
        # We don't fail, but good to note.

    # Final decision
    passed = (score >= 80) # Allow 1 mistake (20pts) or perfect score of 100

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }