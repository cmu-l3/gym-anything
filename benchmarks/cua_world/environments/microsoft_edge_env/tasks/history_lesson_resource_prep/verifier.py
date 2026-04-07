#!/usr/bin/env python3
"""
Verifier for history_lesson_resource_prep task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_history_lesson_resource_prep(traj, env_info, task_info):
    """
    Verifies the History Lesson Resource Prep task.
    
    Criteria:
    1. High-Resolution Download exists (25 pts)
    2. Bookmark created pointing to archives.gov (20 pts)
    3. Bookmark title contains 'Bill of Rights' (10 pts)
    4. Worksheet file exists (10 pts)
    5. Worksheet contains Amendment I text (15 pts)
    6. Worksheet contains Amendment IV text (15 pts)
    7. Precision check: Amendment II NOT included (5 pts)
    
    Total: 100 pts. Pass threshold: 70 pts.
    """
    
    # 1. Retrieve result data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
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
            
    # 2. Evaluate Criteria
    score = 0
    feedback = []
    
    # Download Check (25 pts)
    download = result.get('download', {})
    if download.get('found', False):
        # Additional check on size (should be > 1MB typically, but we accept > 500KB in export)
        # 1MB = 1,000,000 bytes
        if download.get('size_bytes', 0) > 1000000:
             score += 25
             feedback.append("High-res download found (>1MB).")
        else:
             score += 15
             feedback.append("Download found, but smaller than expected for 'High Res' (Partial credit).")
    else:
        feedback.append("No download found in ~/Downloads created during task.")

    # Bookmark Check (20 pts + 10 pts)
    bookmark = result.get('bookmark', {})
    if bookmark.get('found', False):
        score += 20
        feedback.append("Bookmark to archives.gov found.")
        
        title = bookmark.get('title', '').lower()
        if "bill of rights" in title:
            score += 10
            feedback.append("Bookmark title is correct.")
        else:
            feedback.append(f"Bookmark title '{bookmark.get('title')}' does not contain 'Bill of Rights'.")
    else:
        feedback.append("No bookmark pointing to archives.gov found.")

    # Worksheet Check (10 pts)
    worksheet = result.get('worksheet', {})
    content = worksheet.get('content_preview', '').lower()
    
    if worksheet.get('exists', False) and worksheet.get('created_during_task', False):
        score += 10
        feedback.append("Worksheet file exists and was created during task.")
        
        # Amendment I Text (15 pts)
        # Look for key phrase "Congress shall make no law respecting an establishment of religion"
        # We'll use a slightly shorter snippet to be robust against formatting
        if "congress shall make no law" in content and "religion" in content:
            score += 15
            feedback.append("Amendment I text found.")
        else:
            feedback.append("Amendment I text missing or incomplete.")
            
        # Amendment IV Text (15 pts)
        # Key phrase: "right of the people to be secure in their persons"
        if "secure in their persons" in content and "unreasonable searches" in content:
            score += 15
            feedback.append("Amendment IV text found.")
        else:
            feedback.append("Amendment IV text missing or incomplete.")
            
        # Precision Check (5 pts)
        # Ensure they didn't just copy the whole page. Amendment II shouldn't be there.
        # "keep and bear arms"
        if "keep and bear arms" not in content:
            score += 5
            feedback.append("Precision check passed (Amendment II not included).")
        else:
            feedback.append("Precision check failed (File appears to contain extra Amendments).")
            
    else:
        feedback.append("Worksheet file not found or not created during task.")

    # Final scoring
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }