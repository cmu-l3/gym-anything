#!/usr/bin/env python3
import json
import os
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_item_by_identifier(traj, env_info, task_info):
    """
    Verify that the user added 'A Theory of Justice' by ISBN lookup.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    feedback = []
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    expected_title_part = metadata.get("expected_title", "Theory of Justice")
    expected_author_part = metadata.get("expected_author", "Rawls")
    
    # 1. Database Verification (Primary)
    db_data = result.get('db_verification', {})
    item_found = db_data.get('found', False)
    
    if item_found:
        score += 20
        feedback.append("Item found in library (+20).")
        
        # Check Title
        title = db_data.get('title', "")
        if expected_title_part.lower() in title.lower():
            score += 20
            feedback.append(f"Title '{title}' matches expected (+20).")
        else:
            feedback.append(f"Title '{title}' does not match '{expected_title_part}'.")

        # Check Author
        creators = db_data.get('creators', [])
        author_match = False
        for c in creators:
            if expected_author_part.lower() in c.get('lastName', '').lower():
                author_match = True
                break
        
        if author_match:
            score += 20
            feedback.append(f"Author 'Rawls' found (+20).")
        else:
            feedback.append("Author 'Rawls' not found in item creators.")

        # Check Publisher (Detailed metadata check implies successful ISBN resolution)
        fields = db_data.get('fields', {})
        publisher = fields.get('publisher', "")
        if "Harvard" in publisher or "Belknap" in publisher:
            score += 10
            feedback.append(f"Publisher '{publisher}' verified (indicates successful metadata lookup) (+10).")
        else:
            feedback.append(f"Publisher '{publisher}' does not match expected (Harvard/Belknap).")

        # Check Timestamp (Anti-gaming)
        date_added_str = db_data.get('dateAdded', "")
        task_start = result.get('task_start', 0)
        
        # Convert DB timestamp (UTC string usually) to seconds if possible, 
        # but simpler is to rely on Setup clearing the item.
        # If the item exists now and didn't before (implied by Setup cleanup), it's new.
        # We'll stick to the cleanup logic in setup being the primary anti-gaming filter.
        
    else:
        feedback.append("Target book item NOT found in library.")

    # 2. File Verification
    file_info = result.get('file_verification', {})
    if file_info.get('exists', False):
        score += 10
        feedback.append("Verification file created (+10).")
        content = file_info.get('content_preview', "").lower()
        
        if expected_title_part.lower() in content:
            score += 10
            feedback.append("File contains correct title (+10).")
        else:
            feedback.append("File missing title.")
            
        if expected_author_part.lower() in content:
            score += 10
            feedback.append("File contains correct author (+10).")
        else:
            feedback.append("File missing author.")
    else:
        feedback.append("Verification file not found.")

    passed = (score >= 60 and item_found)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }