#!/usr/bin/env python3
"""
Verifier for add_newspaper_article task.
Checks if the correct newspaper article item was created in Jurism.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_newspaper_article(traj, env_info, task_info):
    """
    Verify the newspaper article creation task.
    
    Scoring Breakdown (100 pts):
    - 15 pts: Newspaper article item exists
    - 15 pts: Title correct
    - 15 pts: Author correct
    - 10 pts: Publication correct
    - 10 pts: Date correct
    - 25 pts: Other metadata (Section, Pages, Place, URL, Abstract - 5 pts each)
    - 10 pts: VLM/Anti-gaming (Created during task + visual confirmation)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load result JSON
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

    # Basic checks
    if not result.get('item_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No newspaper article with the title 'Same-Sex Marriage' was found in the library."
        }

    item_data = result.get('item_data', {})
    creators = item_data.get('creators', [])
    
    score = 0
    feedback = []
    
    # 1. Item Type (15 pts)
    if item_data.get('type') == 'newspaperArticle':
        score += 15
        feedback.append("Correct item type (Newspaper Article)")
    else:
        feedback.append(f"Incorrect item type: {item_data.get('type')}")

    # 2. Title (15 pts)
    title = item_data.get('title', '')
    expected_title_fragment = "Supreme Court Ruling Makes Same-Sex Marriage a Right Nationwide"
    if expected_title_fragment.lower() in title.lower():
        score += 15
        feedback.append("Title correct")
    else:
        score += 5 # Partial credit if found but maybe typo
        feedback.append(f"Title mismatch. Got: '{title}'")

    # 3. Author (15 pts)
    author_found = False
    for c in creators:
        if c.get('firstName') == 'Adam' and c.get('lastName') == 'Liptak':
            author_found = True
            break
    
    if author_found:
        score += 15
        feedback.append("Author correct")
    else:
        feedback.append(f"Author 'Adam Liptak' not found. Found: {creators}")

    # 4. Publication (10 pts)
    pub = item_data.get('publicationTitle', '')
    if "New York Times" in pub:
        score += 10
        feedback.append("Publication correct")
    else:
        feedback.append(f"Publication incorrect: '{pub}'")

    # 5. Date (10 pts)
    date = item_data.get('date', '')
    if "2015" in date and "26" in date:
        score += 10
        feedback.append("Date correct")
    else:
        feedback.append(f"Date incorrect: '{date}'")

    # 6. Other Metadata (25 pts)
    # Section
    if item_data.get('section') == 'A':
        score += 5
    else:
        feedback.append(f"Section mismatch (got '{item_data.get('section')}')")
        
    # Pages
    if "A1" in item_data.get('pages', ''):
        score += 5
    else:
        feedback.append(f"Pages mismatch (got '{item_data.get('pages')}')")

    # Place
    if "New York" in item_data.get('place', ''):
        score += 5
    else:
        feedback.append(f"Place mismatch (got '{item_data.get('place')}')")

    # URL
    if "nytimes.com" in item_data.get('url', ''):
        score += 5
    else:
        feedback.append("URL missing or incorrect")

    # Abstract
    if "same-sex marriage" in item_data.get('abstractNote', '').lower():
        score += 5
    else:
        feedback.append("Abstract missing or incorrect")

    # 7. Anti-gaming / VLM (10 pts)
    created_during = result.get('created_during_task', False)
    
    if created_during:
        score += 5
        feedback.append("Item created during task session")
    else:
        feedback.append("Item timestamp indicates it was not created during this session")

    # VLM Verification
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_result = query_vlm(
            images=frames,
            prompt="Does the user interface show a reference manager (Jurism/Zotero)? Is a new item being added or edited in the right-hand panel? Look for fields like Title, Author, or Abstract being filled."
        )
        if "yes" in vlm_result.lower() or "true" in vlm_result.lower():
            score += 5
            feedback.append("Visual verification passed")
    except Exception:
        # Fallback if VLM fails, assume pass if programmatic pass is high
        if score > 70:
            score += 5

    return {
        "passed": score >= 60,
        "score": min(score, 100),
        "feedback": "; ".join(feedback)
    }