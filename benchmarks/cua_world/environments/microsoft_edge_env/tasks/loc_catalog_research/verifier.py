#!/usr/bin/env python3
"""
Verifier for LOC Catalog Research task.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_loc_research(traj, env_info, task_info):
    """
    Verify the shelf list file matches the expected Library of Congress data.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_books = metadata.get('books', [])
    
    # 2. Get Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Analyze Results
    score = 0
    feedback = []
    
    # Check 1: File Existence & Anti-Gaming (20 pts)
    if not result.get("output_file_exists"):
        return {"passed": False, "score": 0, "feedback": "Shelf list file not found."}
    
    if not result.get("output_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "File timestamp indicates it was not created during the task."}
    
    score += 10 # File exists and is new
    feedback.append("File created successfully.")

    # Check 2: Browser History (10 pts)
    if result.get("history_visits_new", 0) > 0:
        score += 10
        feedback.append("Browser history confirms LOC catalog usage.")
    else:
        feedback.append("WARNING: No history of visiting catalog.loc.gov found.")

    # Check 3: Content Verification (70 pts total)
    content = result.get("output_file_content", "").strip()
    lines = [l.strip() for l in content.split('\n') if l.strip()]
    
    if len(lines) < 3:
        feedback.append(f"Expected 3 lines of data, found {len(lines)}.")
    
    # Helper to check book data
    def check_book_entry(isbn, target_lccn, target_call_pattern, lines):
        # Find line containing ISBN
        for line in lines:
            if isbn in line:
                # Check LCCN
                lccn_found = target_lccn in line
                
                # Check Call Number (Regex)
                call_match = re.search(target_call_pattern, line, re.IGNORECASE)
                
                return lccn_found, bool(call_match), line
        return False, False, None

    points_per_book = 23 # roughly 70/3
    
    for i, book in enumerate(expected_books):
        isbn = book['isbn']
        lccn = book['lccn']
        pattern = book['call_number_pattern']
        title_hint = book.get('title_hint', f"Book {i+1}")
        
        lccn_ok, call_ok, line_found = check_book_entry(isbn, lccn, pattern, lines)
        
        book_score = 0
        status_parts = []
        
        if line_found:
            # 5 pts for finding the record (ISBN match)
            # 10 pts for correct Call Number
            # 8 pts for correct LCCN
            if call_ok:
                book_score += 13
                status_parts.append("Call Number correct")
            else:
                status_parts.append("Call Number incorrect")
                
            if lccn_ok:
                book_score += 10
                status_parts.append("LCCN correct")
            else:
                status_parts.append("LCCN incorrect")
                
            score += book_score
            feedback.append(f"{title_hint}: {', '.join(status_parts)}")
        else:
            feedback.append(f"{title_hint}: ISBN {isbn} not found in output.")

    # Formatting check (bonus/rounding)
    if "|" in content:
        # If we are close to 100, give full points for formatting
        pass
    else:
         feedback.append("Incorrect file format (missing '|' delimiter).")
         score = max(0, score - 5)

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }