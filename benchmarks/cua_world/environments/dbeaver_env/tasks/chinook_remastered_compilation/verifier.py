#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_remastered_compilation(traj, env_info, task_info):
    """
    Verify the Chinook Remastered Compilation task.
    
    Scoring Breakdown (100 pts):
    - 10 pts: CSV file exists
    - 10 pts: SQL file exists
    - 20 pts: New Album created with correct title/artist
    - 20 pts: Correct number of tracks (10) in the new album
    - 20 pts: Data Transformation (Price 1.29 & Name Suffix)
    - 20 pts: Content Accuracy (Tracks match the Top 10 best sellers)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Deliverables (20 pts)
    if result.get('csv_exists'):
        score += 10
        feedback.append("CSV manifest found.")
    else:
        feedback.append("Missing CSV manifest.")

    if result.get('sql_exists'):
        score += 10
        feedback.append("SQL script found.")
    else:
        feedback.append("Missing SQL script.")

    # 2. Album Creation (20 pts)
    if result.get('album_found'):
        score += 20
        feedback.append("Album 'Iron Maiden: Remastered Classics' created successfully.")
    else:
        feedback.append("Album 'Iron Maiden: Remastered Classics' NOT found or linked to wrong Artist.")
        # If album missing, they likely failed the core task, so stop here to avoid confusion? 
        # No, continue scoring what exists.

    # 3. Track Count (20 pts)
    track_count = result.get('track_count', 0)
    if track_count == 10:
        score += 20
        feedback.append("Correct number of tracks (10) created.")
    elif track_count > 0:
        partial = int((track_count / 10.0) * 10) # 1 pt per track up to 10
        score += partial
        feedback.append(f"Incorrect track count: {track_count} (Expected 10).")
    else:
        feedback.append("No tracks found in the new album.")

    # 4. Data Transformation (Price & Name) (20 pts)
    # We expect 10 tracks. If they have 10 tracks, max score 20.
    # We will score based on percentage of tracks that are correct.
    if track_count > 0:
        price_count = result.get('correct_price_count', 0)
        suffix_count = result.get('suffix_match_count', 0)
        
        # Max 10 pts for price
        price_score = min(10, int((price_count / 10.0) * 10))
        score += price_score
        
        # Max 10 pts for suffix
        suffix_score = min(10, int((suffix_count / 10.0) * 10))
        score += suffix_score
        
        if price_count < track_count:
             feedback.append(f"Only {price_count}/{track_count} tracks had correct price (1.29).")
        if suffix_count < track_count:
             feedback.append(f"Only {suffix_count}/{track_count} tracks had correct name suffix.")
    
    # 5. Content Accuracy (20 pts)
    # Did they pick the RIGHT songs?
    content_match = result.get('content_match_count', 0)
    if content_match == 10:
        score += 20
        feedback.append("All remastered tracks match the Top 10 best-sellers.")
    elif content_match > 0:
        partial = int(content_match * 2)
        score += partial
        feedback.append(f"Only {content_match}/10 tracks match the actual Top 10 best-sellers.")
    else:
        feedback.append("None of the created tracks match the Top 10 best-sellers (wrong source tracks selected).")

    # Pass threshold
    passed = (score >= 65) and result.get('album_found') and (track_count >= 5)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }