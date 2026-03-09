#!/usr/bin/env python3
"""
Verifier for Civil Rights Timeline task.

Scoring (100 points, pass at 70):
1. File Existence & Validity (15 pts)
2. Page Count == 2 (10 pts)
3. Title Page Content (10 pts)
4. Event Content (10 pts each, max 50 pts)
5. Visual Structure (Line + Shapes) (15 pts)

Also includes VLM verification for visual layout confirmation.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_civil_rights_timeline(traj, env_info, task_info):
    """
    Verify the creation of the Civil Rights timeline flipchart.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # 1. Load JSON Result from container
    try:
        tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp_file.name
        tmp_file.close()
        
        copy_from_env('/tmp/task_result.json', tmp_path)
        
        with open(tmp_path, 'r') as f:
            result = json.load(f)
            
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {str(e)}"}

    score = 0
    feedback = []

    # --- Criterion 1: File Existence & Validity (15 pts) ---
    if result.get('file_found') and result.get('file_valid') and result.get('created_during_task'):
        score += 15
        feedback.append("File created successfully (15/15)")
    elif result.get('file_found'):
        score += 5
        feedback.append("File exists but is invalid or pre-existing (5/15)")
    else:
        return {"passed": False, "score": 0, "feedback": "No flipchart file found"}

    # --- Criterion 2: Page Count (10 pts) ---
    page_count = result.get('page_count', 0)
    if page_count == 2:
        score += 10
        feedback.append("Correct page count: 2 (10/10)")
    else:
        feedback.append(f"Incorrect page count: {page_count}, expected 2 (0/10)")

    # --- Criterion 3: Title Page Content (10 pts) ---
    if result.get('has_title') and result.get('has_date_range'):
        score += 10
        feedback.append("Title and date range present (10/10)")
    elif result.get('has_title'):
        score += 5
        feedback.append("Title present, date range missing (5/10)")
    else:
        feedback.append("Title missing (0/10)")

    # --- Criterion 4: Events (50 pts total, 10 per event) ---
    events = result.get('events', {})
    event_score = 0
    event_score += 10 if events.get('brown_v_board') else 0
    event_score += 10 if events.get('montgomery') else 0
    event_score += 10 if events.get('march_washington') else 0
    event_score += 10 if events.get('civil_rights_act') else 0
    event_score += 10 if events.get('voting_rights_act') else 0
    
    score += event_score
    feedback.append(f"Events identified: {event_score/10}/5 ({event_score}/50)")

    # --- Criterion 5: Visual Structure (15 pts) ---
    # Line (10 pts) + Shapes (5 pts)
    struct_score = 0
    if result.get('has_line'):
        struct_score += 10
        feedback.append("Timeline axis found (10/10)")
    else:
        feedback.append("Timeline axis line missing (0/10)")
        
    shape_count = result.get('shape_count', 0)
    if shape_count >= 5:
        struct_score += 5
        feedback.append(f"Shape markers found: {shape_count} (5/5)")
    else:
        feedback.append(f"Insufficient shape markers: {shape_count} (0/5)")
    
    score += struct_score

    # --- VLM Sanity Check (Bonus/Verification) ---
    # If score is passing (>70), use VLM to ensure it's not a false positive 
    # (e.g., just text list without actual timeline layout)
    if score >= 70:
        query_vlm = env_info.get('query_vlm')
        final_screenshot = get_final_screenshot(traj)
        
        if query_vlm and final_screenshot:
            vlm_prompt = """
            Look at this ActivInspire flipchart page. 
            Does it visually resemble a timeline? 
            I am looking for:
            1. A horizontal line across the page.
            2. Markers (shapes) placed along the line.
            3. Text labels near the markers.
            
            Return JSON: {"is_timeline": true/false, "confidence": "high/med/low"}
            """
            try:
                vlm_res = query_vlm(prompt=vlm_prompt, image=final_screenshot)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if not parsed.get('is_timeline', False):
                        feedback.append("WARNING: VLM did not visually confirm timeline layout.")
                        # We don't deduct points heavily for VLM to avoid false negatives, 
                        # but we note it.
            except Exception:
                pass

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }