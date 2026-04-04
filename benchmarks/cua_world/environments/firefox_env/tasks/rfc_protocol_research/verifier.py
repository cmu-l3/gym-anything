#!/usr/bin/env python3
"""
Verifier for rfc_protocol_research task.

Verifies:
1. rfc_reference.json exists, is fresh, and contains correct metadata for RFC 9113, 8446, 9110.
2. Firefox history shows visits to RFC Editor/IETF.
3. Firefox bookmarks contain an 'RFC Research' folder with links.

Scoring (100 pts):
- JSON File Exists & Valid: 10 pts
- Correct Keys (rfc9113, rfc8446, rfc9110): 10 pts
- Content Accuracy (Titles/Dates/Authors): 45 pts (15 per RFC)
- Firefox History: 10 pts
- Bookmark Structure: 15 pts (5 for folder, 10 for contents)
- Bookmarks point to valid domains: 10 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_rfc_protocol_research(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Retrieve export result (browser state)
    browser_state = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                browser_state = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load task_result.json: {e}")
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # 2. Retrieve user's JSON file
    user_json = {}
    json_load_success = False
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        try:
            copy_from_env("/home/ga/Documents/rfc_reference.json", tmp.name)
            with open(tmp.name, 'r') as f:
                user_json = json.load(f)
            json_load_success = True
        except Exception as e:
            logger.warning(f"Failed to load user json: {e}")
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # Metadata / Ground Truth
    ground_truth = task_info.get('metadata', {}).get('ground_truth', {})
    
    score = 0
    feedback = []

    # CRITERION 1: Browser History (10 pts)
    visits = browser_state.get('history_visits', 0)
    if visits >= 3:
        score += 10
        feedback.append(f"Browser history shows {visits} RFC site visits (+10)")
    elif visits > 0:
        score += 5
        feedback.append(f"Browser history shows minimal RFC site visits (+5)")
    else:
        feedback.append("No browser history for RFC sites found (+0)")

    # CRITERION 2: Bookmarks (25 pts)
    folder_exists = browser_state.get('rfc_folder_exists', False)
    bm_count = browser_state.get('rfc_bookmark_count', 0)
    valid_urls = browser_state.get('rfc_correct_url_count', 0)

    if folder_exists:
        score += 5
        feedback.append("'RFC Research' folder created (+5)")
        
        if bm_count >= 3:
            score += 10
            feedback.append(f"Folder contains {bm_count} bookmarks (+10)")
        elif bm_count > 0:
            score += 5
            feedback.append(f"Folder contains {bm_count} bookmarks (expected 3+) (+5)")
            
        if valid_urls >= 3:
            score += 10
            feedback.append(f"Bookmarks point to valid IETF/RFC domains (+10)")
        elif valid_urls > 0:
            score += 5
            feedback.append("Some bookmarks point to valid domains (+5)")
    else:
        feedback.append("'RFC Research' bookmark folder not found (+0)")

    # CRITERION 3: JSON File Structure (20 pts)
    if browser_state.get('json_fresh', False) and json_load_success:
        score += 10
        feedback.append("JSON file created and is valid (+10)")
        
        keys_present = 0
        required_keys = ['rfc9113', 'rfc8446', 'rfc9110']
        for k in required_keys:
            if k in user_json:
                keys_present += 1
        
        if keys_present == 3:
            score += 10
            feedback.append("All required RFC keys present (+10)")
        else:
            score += int((keys_present / 3) * 10)
            feedback.append(f"Found {keys_present}/3 RFC keys (+{int((keys_present/3)*10)})")
            
    else:
        feedback.append("JSON file missing, invalid, or not created during task (+0)")
        return {"passed": False, "score": score, "feedback": "; ".join(feedback)}

    # CRITERION 4: Content Verification (45 pts)
    content_score = 0
    
    for rfc_key, expected in ground_truth.items():
        entry = user_json.get(rfc_key, {})
        if not entry:
            continue
            
        rfc_pts = 0
        
        # Check Title
        title = entry.get('title', '').lower()
        title_ok = any(kw.lower() in title for kw in expected.get('title_keywords', []))
        if title_ok:
            rfc_pts += 5
        
        # Check Date
        date = entry.get('publication_date', '')
        if expected.get('date') in date: # Simple substring match for YYYY-MM
            rfc_pts += 3
            
        # Check Author
        authors = entry.get('authors', [])
        # Handle list or string
        if isinstance(authors, str):
            authors = [authors]
        author_ok = any(expected.get('author_keyword').lower() in str(a).lower() for a in authors)
        if author_ok:
            rfc_pts += 5
            
        # Check Status
        status = entry.get('status', '').lower()
        if expected.get('status_keyword').lower() in status:
            rfc_pts += 2
            
        content_score += rfc_pts
        feedback.append(f"{rfc_key}: {rfc_pts}/15 pts")

    score += content_score
    
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }