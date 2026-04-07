#!/usr/bin/env python3
"""Verifier for create_bolo_person task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_bolo_person(traj, env_info, task_info):
    """
    Verify that a Person BOLO was correctly created.
    
    Scoring Criteria:
    1. Record Created (20 pts): A new record exists in bolos_persons table.
    2. Name Match (30 pts): First and Last name match "Marcus Holloway".
    3. Gender Match (10 pts): Gender is "Male".
    4. Location Match (15 pts): Last seen contains "Vinewood".
    5. Description/Keywords (25 pts): Checks for presence of keywords from the detailed description 
       (hoodie, tattoo, 185, 6'1, etc.) in any of the descriptive fields.
    
    Pass Threshold: 60 points
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('expected_first_name', 'Marcus').lower()
    expected_lname = metadata.get('expected_last_name', 'Holloway').lower()
    expected_gender = metadata.get('expected_gender', 'Male').lower()
    expected_location = metadata.get('expected_location', 'Vinewood').lower()
    description_keywords = metadata.get('description_keywords', ["hoodie", "tattoo", "185", "blue", "sneakers"])

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_bolo_person_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if record exists
    if not result.get('bolo_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new Person BOLO record found in the database."
        }
    
    score += 20
    feedback_parts.append("BOLO record created")
    
    bolo = result.get('bolo', {})
    
    # 2. Name Match (30 pts split)
    fname = (bolo.get('first_name') or '').strip().lower()
    lname = (bolo.get('last_name') or '').strip().lower()
    
    if expected_fname in fname:
        score += 15
        feedback_parts.append(f"First name match ({bolo.get('first_name')})")
    else:
        feedback_parts.append(f"First name mismatch (Expected: {expected_fname}, Got: {fname})")

    if expected_lname in lname:
        score += 15
        feedback_parts.append(f"Last name match ({bolo.get('last_name')})")
    else:
        feedback_parts.append(f"Last name mismatch (Expected: {expected_lname}, Got: {lname})")
        
    # 3. Gender Match (10 pts)
    sex = (bolo.get('sex') or '').strip().lower()
    if sex == expected_gender or sex == 'm':
        score += 10
        feedback_parts.append("Gender match")
    else:
        feedback_parts.append(f"Gender mismatch (Expected: {expected_gender}, Got: {sex})")

    # 4. Location Match (15 pts)
    last_seen = (bolo.get('last_seen') or '').strip().lower()
    if expected_location in last_seen:
        score += 15
        feedback_parts.append("Location match")
    else:
        feedback_parts.append(f"Location mismatch (Expected partial: {expected_location}, Got: {last_seen})")

    # 5. Description Keywords (25 pts)
    # Combine all fields that might contain description data
    combined_desc = (
        (bolo.get('description_combined') or '') + " " +
        (bolo.get('race') or '') + " " +
        (bolo.get('height') or '') + " " +
        (bolo.get('weight') or '') + " " +
        (bolo.get('hair_color') or '')
    ).lower()

    matches = [kw for kw in description_keywords if kw.lower() in combined_desc]
    match_count = len(matches)
    
    # Scoring: 5 points per keyword up to 25
    kw_score = min(25, match_count * 5)
    score += kw_score
    
    if match_count > 0:
        feedback_parts.append(f"Description keywords matched: {', '.join(matches)}")
    else:
        feedback_parts.append("No description keywords matched")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }