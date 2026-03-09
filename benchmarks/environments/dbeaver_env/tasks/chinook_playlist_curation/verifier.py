#!/usr/bin/env python3
"""
Verifier for Chinook Playlist Curation Task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_playlist_curation(traj, env_info, task_info):
    """
    Verify playlist creation in SQLite database.
    
    Scoring Breakdown:
    - Connection 'Chinook' exists: 5 pts
    - Playlist 'Long Rock Anthems' created correctly: 25 pts (5 exists, 15 count, 5 logic)
    - Playlist 'Global Bestsellers' created correctly: 25 pts (5 exists, 10 count, 10 logic)
    - Playlist 'Hidden Gems' created correctly: 20 pts (5 exists, 10 count, 5 logic)
    - CSV Export correct: 20 pts
    - SQL Script saved: 5 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Connection (5 pts)
    if result.get('connection_exists'):
        score += 5
        feedback_parts.append("[OK] DBeaver connection 'Chinook' found.")
    else:
        feedback_parts.append("[FAIL] DBeaver connection 'Chinook' missing.")

    # 2. SQL Script (5 pts)
    if result.get('sql_exists') and result.get('sql_modified'):
        score += 5
        feedback_parts.append("[OK] SQL script saved.")
    else:
        feedback_parts.append("[FAIL] SQL script missing or not new.")

    # 3. Playlists Verification
    playlists = result.get('playlists_created', {})
    
    # Long Rock Anthems (25 pts)
    lra = playlists.get('long_rock_anthems', {})
    if lra.get('exists'):
        score += 5
        if lra.get('track_count_match'):
            score += 15
            if lra.get('logic_check_pass'):
                score += 5
                feedback_parts.append("[OK] 'Long Rock Anthems' perfect.")
            else:
                feedback_parts.append("[PARTIAL] 'Long Rock Anthems' created but contains invalid tracks.")
        else:
            feedback_parts.append(f"[FAIL] 'Long Rock Anthems' has wrong track count ({lra.get('track_count')}).")
    else:
        feedback_parts.append("[FAIL] 'Long Rock Anthems' playlist not found.")

    # Global Bestsellers (25 pts)
    gb = playlists.get('global_bestsellers', {})
    if gb.get('exists'):
        score += 5
        if gb.get('track_count_match'):
            score += 10
            if gb.get('logic_check_pass'):
                score += 10
                feedback_parts.append("[OK] 'Global Bestsellers' perfect.")
            else:
                feedback_parts.append("[PARTIAL] 'Global Bestsellers' created but track selection logic incorrect.")
        else:
            feedback_parts.append(f"[FAIL] 'Global Bestsellers' has wrong track count ({gb.get('track_count')}).")
    else:
        feedback_parts.append("[FAIL] 'Global Bestsellers' playlist not found.")

    # Hidden Gems (20 pts)
    hg = playlists.get('hidden_gems', {})
    if hg.get('exists'):
        score += 5
        if hg.get('track_count_match'):
            score += 10
            if hg.get('logic_check_pass'):
                score += 5
                feedback_parts.append("[OK] 'Hidden Gems' perfect.")
            else:
                feedback_parts.append("[PARTIAL] 'Hidden Gems' created but contains purchased tracks.")
        else:
            feedback_parts.append(f"[FAIL] 'Hidden Gems' has wrong track count ({hg.get('track_count')}).")
    else:
        feedback_parts.append("[FAIL] 'Hidden Gems' playlist not found.")

    # 4. CSV Export (20 pts)
    if result.get('csv_exists') and result.get('csv_content_valid'):
        score += 20
        feedback_parts.append("[OK] Summary CSV exported correctly.")
    elif result.get('csv_exists'):
        score += 10
        feedback_parts.append("[PARTIAL] CSV exists but content/format is incorrect.")
    else:
        feedback_parts.append("[FAIL] Summary CSV not found.")

    passed = (score >= 60) and result.get('connection_exists') and (gb.get('exists') or lra.get('exists'))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }