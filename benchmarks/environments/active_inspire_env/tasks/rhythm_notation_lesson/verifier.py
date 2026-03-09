#!/usr/bin/env python3
"""
Verifier for rhythm_notation_lesson task.

Scoring System (100 points total, pass at 70):
1. File Verification (15 pts): File exists, is valid zip/xml, created during task.
2. Page Structure (10 pts): Exactly 4 pages.
3. Content - Note Names (32 pts): 8 pts for each (Whole, Half, Quarter, Eighth).
4. Content - Title (10 pts): "Rhythm" present.
5. Content - Beat Values (10 pts): Beat counts mentioned.
6. Content - Shapes (13 pts): At least 4 circles/ellipses (for note heads).
7. Content - Activity (10 pts): "Clap" or "Practice" text found.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_rhythm_notation_lesson(traj, env_info, task_info):
    """
    Verify the Rhythm Notation Lesson flipchart task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    # Retrieve result JSON from the environment
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_path)
            with open(tmp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve verification results: {e}"
        }

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Verification (15 pts) ---
    file_found = result.get('file_found', False)
    file_valid = result.get('file_valid', False)
    created_during = result.get('created_during_task', False)

    if file_found and file_valid and created_during:
        score += 15
        feedback_parts.append("File created successfully (15/15)")
    elif file_found and file_valid:
        # Penalize for potentially using pre-existing file (anti-gaming)
        # But if the script cleaned up correctly, this might be a clock skew issue
        # Giving partial credit if content is correct
        score += 5
        feedback_parts.append("File exists but timestamp issue (5/15)")
    elif file_found:
        score += 5
        feedback_parts.append("File exists but invalid format (5/15)")
    else:
        feedback_parts.append("File not found (0/15)")
        # Critical failure, stop here or continue? 
        # Usually stop if file missing, but we'll continue to show what else failed.
        return {"passed": False, "score": 0, "feedback": "File not found: rhythm_basics.flipchart"}

    # --- Criterion 2: Page Structure (10 pts) ---
    page_count = result.get('page_count', 0)
    if page_count == 4:
        score += 10
        feedback_parts.append("Correct page count: 4 (10/10)")
    else:
        feedback_parts.append(f"Incorrect page count: {page_count}, expected 4 (0/10)")

    # --- Criterion 3: Note Names (32 pts) ---
    notes_found = 0
    note_terms = []
    if result.get('has_whole_note'):
        notes_found += 1
        note_terms.append("Whole")
    if result.get('has_half_note'):
        notes_found += 1
        note_terms.append("Half")
    if result.get('has_quarter_note'):
        notes_found += 1
        note_terms.append("Quarter")
    if result.get('has_eighth_note'):
        notes_found += 1
        note_terms.append("Eighth")
    
    note_score = notes_found * 8
    score += note_score
    if notes_found == 4:
        feedback_parts.append("All 4 note types found (32/32)")
    else:
        feedback_parts.append(f"Found {notes_found}/4 note types: {', '.join(note_terms)} ({note_score}/32)")

    # --- Criterion 4: Title (10 pts) ---
    if result.get('has_title_rhythm'):
        score += 10
        feedback_parts.append("Title 'Rhythm' found (10/10)")
    else:
        feedback_parts.append("Title 'Rhythm' missing (0/10)")

    # --- Criterion 5: Beat Values (10 pts) ---
    if result.get('has_beat_values'):
        score += 10
        feedback_parts.append("Beat values found (10/10)")
    else:
        feedback_parts.append("Beat values missing (0/10)")

    # --- Criterion 6: Shapes (13 pts) ---
    shape_count = result.get('circle_ellipse_count', 0)
    if shape_count >= 4:
        score += 13
        feedback_parts.append(f"Sufficient note head shapes: {shape_count} (13/13)")
    elif shape_count > 0:
        score += 5
        feedback_parts.append(f"Some shapes found: {shape_count}, expected >=4 (5/13)")
    else:
        feedback_parts.append("No circle/ellipse shapes found for notes (0/13)")

    # --- Criterion 7: Activity (10 pts) ---
    if result.get('has_clap_activity'):
        score += 10
        feedback_parts.append("Clap activity found (10/10)")
    else:
        feedback_parts.append("Clap activity missing (0/10)")

    # Final Verification
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }