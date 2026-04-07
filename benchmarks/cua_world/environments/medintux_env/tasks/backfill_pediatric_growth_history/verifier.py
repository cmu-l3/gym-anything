#!/usr/bin/env python3
"""
Verifier for backfill_pediatric_growth_history task.

Verifies:
1. That 4 distinct notes exist for the patient in the database.
2. That the notes correspond to the requested historical dates (DB column Rub_Date).
3. That the notes contain the correct weight/height values in their text.
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_backfill_pediatric_growth_history(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_entries = metadata.get('expected_entries', [])
    
    # Load result from environment
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

    # Extract DB data
    db_data = result.get('db_data', {})
    notes = db_data.get('notes', [])
    app_running = result.get('app_was_running', False)
    
    score = 0
    feedback_parts = []
    
    # 1. Check if ANY notes exist (10 pts)
    if len(notes) > 0:
        score += 10
        feedback_parts.append("Found patient notes")
    else:
        return {"passed": False, "score": 0, "feedback": "No notes found for patient Lucas GRANDJEAN"}
        
    # 2. Check quantity of notes (20 pts)
    # We expect at least 4 notes (one for each date).
    if len(notes) >= 4:
        score += 20
        feedback_parts.append("Correct number of notes created")
    else:
        feedback_parts.append(f"Found {len(notes)} notes, expected 4")
        
    # 3. Verify specific entries (Dates: 40 pts, Data: 30 pts)
    # Strategy: For each expected entry, look for a matching note in the DB
    
    matched_dates = 0
    matched_data = 0
    
    for expected in expected_entries:
        target_date = expected['date'] # YYYY-MM-DD
        target_weight = str(expected['weight'])
        target_height = str(expected['height'])
        
        # Find note with this date
        # Note: Rub_Date from DB usually comes as YYYY-MM-DD string or datetime object converted to string
        matching_note = None
        for note in notes:
            # Flexible date matching (check if target_date is in the note's date string)
            if target_date in str(note.get('date', '')):
                matching_note = note
                break
        
        if matching_note:
            matched_dates += 1
            # Check content
            text = matching_note.get('text', '').lower()
            # We look for the numbers. 
            # Note: 10.2 might appear as "10,2" in French locale, so we should be lenient?
            # The prompt provided "10.2 kg", let's assume agent enters what is in text file.
            # But MedinTux might store it differently if fields are used. 
            # Usually Rub_Texte is just the free text blob.
            
            # Replace comma with dot for checking
            text_normalized = text.replace(',', '.')
            
            has_weight = target_weight in text_normalized
            has_height = target_height in text_normalized
            
            if has_weight and has_height:
                matched_data += 1
                feedback_parts.append(f"✓ {target_date}: Data verified")
            else:
                feedback_parts.append(f"⚠ {target_date}: Date found, but missing values ({target_weight}/{target_height})")
        else:
            feedback_parts.append(f"✗ {target_date}: Note missing")

    # Score calculation for dates (10 pts per date)
    score += (matched_dates * 10)
    
    # Score calculation for data content (7.5 pts per correct entry)
    score += (matched_data * 7.5)
    
    # Cap score at 100
    score = min(100, score)
    score = int(score)
    
    passed = (score >= 70)
    
    feedback = f"Score: {score}/100. " + "; ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "notes_found": len(notes),
            "matched_dates": matched_dates,
            "matched_data": matched_data
        }
    }