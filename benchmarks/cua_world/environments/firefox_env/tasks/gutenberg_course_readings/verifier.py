#!/usr/bin/env python3
"""
Verifier for gutenberg_course_readings task.

Scoring Breakdown (100 points total):
1. Text Files (50 pts total):
   - Existence (15 pts): 3 pts per file at correct path
   - Size (15 pts): 3 pts per file > 50KB (prevents empty files)
   - Content (20 pts): 4 pts per file containing specific fingerprint text
2. JSON Metadata (20 pts total):
   - Valid JSON & Structure (15 pts): Contains 'texts' list with required fields
   - IDs Correct (5 pts): Gutenberg IDs match expected values
3. Browser Evidence (20 pts total):
   - History (10 pts): Visited gutenberg.org
   - Bookmarks (10 pts): 'Course Readings' folder exists with >=3 Gutenberg links
4. Freshness (10 pts):
   - Files created after task start timestamp

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_IDS = {
    "pride_and_prejudice.txt": 1342,
    "frankenstein.txt": 84,
    "great_expectations.txt": 1400,
    "dorian_gray.txt": 174,
    "heart_of_darkness.txt": 219
}

def verify_gutenberg_readings(traj, env_info, task_info):
    """Verify Gutenberg Course Readings task."""
    
    # 1. Retrieve result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    result_path = "/tmp/task_result.json"
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        local_path = tmp.name
    
    try:
        copy_from_env(result_path, local_path)
        with open(local_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data"}
    finally:
        if os.path.exists(local_path):
            os.unlink(local_path)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Files (50 pts) ---
    files = data.get("files", [])
    files_exist_count = 0
    files_size_count = 0
    files_content_count = 0
    files_fresh_count = 0
    
    for f in files:
        fname = os.path.basename(f.get("path", ""))
        
        # Existence (3 pts each)
        if f.get("exists"):
            score += 3
            files_exist_count += 1
            
            # Freshness check (tracked separately, awarded later)
            if f.get("fresh"):
                files_fresh_count += 1
                
            # Size check (3 pts each) - ensure not empty
            # 50KB is safe lower bound for these novels
            if f.get("size", 0) > 51200: 
                score += 3
                files_size_count += 1
            
            # Content check (4 pts each)
            if f.get("content_match"):
                score += 4
                files_content_count += 1
        else:
            feedback_parts.append(f"Missing file: {fname}")

    if files_exist_count == 5:
        feedback_parts.append("All 5 text files created")
    
    # --- Criterion 2: Freshness (10 pts) ---
    # Awarded if all existing files are fresh (and at least 1 exists)
    if files_exist_count > 0 and files_fresh_count == files_exist_count:
        score += 10
        feedback_parts.append("Files created during task session (+10)")
    elif files_exist_count > 0:
        feedback_parts.append("Some files pre-dated task start (0 pts for freshness)")

    # --- Criterion 3: JSON Metadata (20 pts) ---
    json_info = data.get("json_file", {})
    json_score = 0
    
    if json_info.get("exists") and json_info.get("valid"):
        content = json_info.get("content", {})
        texts = content.get("texts", [])
        
        # Check structure
        if isinstance(texts, list) and len(texts) >= 5:
            # Check for required keys in at least 5 entries
            valid_entries = 0
            ids_correct = 0
            
            for entry in texts:
                keys = ["title", "author", "year", "gutenberg_id", "file_path"]
                if all(k in entry for k in keys):
                    valid_entries += 1
                    
                    # Check ID matching
                    path = entry.get("file_path", "")
                    gid = entry.get("gutenberg_id")
                    
                    # Try to match ID to filename
                    for expected_fname, expected_id in EXPECTED_IDS.items():
                        if expected_fname in path and gid == expected_id:
                            ids_correct += 1
                            break
            
            if valid_entries >= 5:
                score += 15
                feedback_parts.append("Reading list JSON valid with 5 entries (+15)")
            else:
                score += 5
                feedback_parts.append("Reading list JSON exists but incomplete entries (+5)")
                
            if ids_correct >= 5:
                score += 5
                feedback_parts.append("Gutenberg IDs correct (+5)")
            else:
                feedback_parts.append(f"Gutenberg IDs mismatch ({ids_correct}/5 correct)")
        else:
            score += 5
            feedback_parts.append("Reading list JSON valid but missing 'texts' array or too few entries (+5)")
    else:
        feedback_parts.append("Reading list JSON missing or invalid")

    # --- Criterion 4: Browser Evidence (20 pts) ---
    browser = data.get("browser_data", {})
    
    # History (10 pts)
    visits = browser.get("gutenberg_visits", 0)
    if visits > 0:
        score += 10
        feedback_parts.append(f"Gutenberg history verified ({visits} visits) (+10)")
    else:
        feedback_parts.append("No Gutenberg visits found in history")
        
    # Bookmarks (10 pts)
    folder_exists = browser.get("bookmark_folder_exists")
    valid_bookmarks = browser.get("valid_gutenberg_bookmarks", 0)
    
    if folder_exists:
        if valid_bookmarks >= 3:
            score += 10
            feedback_parts.append(f"Bookmark folder verified with {valid_bookmarks} Gutenberg links (+10)")
        elif valid_bookmarks >= 1:
            score += 5
            feedback_parts.append(f"Bookmark folder exists but few links ({valid_bookmarks}) (+5)")
        else:
            score += 2
            feedback_parts.append("Bookmark folder exists but empty/wrong links (+2)")
    else:
        feedback_parts.append("Bookmark folder 'Course Readings' not found")

    # Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }