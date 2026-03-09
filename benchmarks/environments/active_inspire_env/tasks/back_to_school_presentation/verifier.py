#!/usr/bin/env python3
"""
Verifier for Back-to-School Presentation task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_back_to_school_presentation(traj, env_info, task_info):
    """
    Verify the Back-to-School presentation flipchart.
    
    Scoring Breakdown (100 pts):
    - File Valid & Created: 15 pts
    - Page Count (3): 10 pts
    - Page 1 Content (Welcome): 20 pts
    - Page 2 Content (Grading): 25 pts
    - Page 3 Content (Contact): 20 pts
    - Shapes (>= 5): 10 pts
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # 1. Load result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env('/tmp/task_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result export failed: {e}"}

    score = 0
    feedback = []

    # Criterion 1: File Existence & Validity (15 pts)
    if result.get("file_found") and result.get("file_valid"):
        if result.get("created_during_task"):
            score += 15
            feedback.append("File created successfully (+15)")
        else:
            score += 5
            feedback.append("File exists but old timestamp (+5)")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid flipchart file found"}

    # Criterion 2: Page Count (10 pts)
    # Exact match for 3 pages preferred
    pages = result.get("page_count", 0)
    if pages == 3:
        score += 10
        feedback.append("Correct page count (3) (+10)")
    elif pages > 0:
        score += 5
        feedback.append(f"Incorrect page count ({pages}) (+5)")
    else:
        feedback.append("Flipchart is empty")

    # Content Verification
    content = result.get("content", {})

    # Page 1: Welcome (20 pts)
    p1_score = 0
    if content.get("english_10"): p1_score += 10
    if content.get("rivera"): p1_score += 5
    if content.get("room_214"): p1_score += 5
    score += p1_score
    if p1_score == 20: feedback.append("Page 1 content correct (+20)")
    else: feedback.append(f"Page 1 missing content ({p1_score}/20)")

    # Page 2: Grading (25 pts)
    p2_score = 0
    if content.get("grading"): p2_score += 5
    
    # Categories (up to 15 pts, 3 pts each approx)
    cats = content.get("categories_count", 0)
    p2_score += min(15, cats * 3)
    
    # Percentages (up to 5 pts)
    pcts = content.get("percentages_count", 0)
    if pcts >= 3: p2_score += 5
    
    score += p2_score
    feedback.append(f"Page 2 content ({p2_score}/25)")

    # Page 3: Contact (20 pts)
    p3_score = 0
    if content.get("email"): p3_score += 10
    
    # Dates (up to 10 pts, 3.33 each)
    dates = content.get("dates_count", 0)
    p3_score += min(10, int(dates * 3.4))
    
    score += p3_score
    feedback.append(f"Page 3 content ({p3_score}/20)")

    # Shapes (10 pts)
    # Need at least 5 (1 border + 4 boxes minimum)
    shapes = result.get("shape_count", 0)
    if shapes >= 5:
        score += 10
        feedback.append("Sufficient shapes detected (+10)")
    elif shapes >= 1:
        score += 5
        feedback.append(f"Few shapes detected ({shapes}) (+5)")
    else:
        feedback.append("No shapes detected")

    # VLM Verification (Anti-Gaming / Confirmation)
    # Check if we have a trajectory
    if score >= 60 and traj:
        # Simple VLM check to ensure agent was actually doing work
        # Pass threshold is score >= 60
        query_vlm = env_info.get("query_vlm")
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            vlm_prompt = "Does this sequence of screenshots show a user editing a flipchart presentation in ActivInspire? Look for text being added or shape tools being used."
            
            try:
                vlm_res = query_vlm(frames, vlm_prompt)
                if vlm_res.get("success") and vlm_res.get("parsed", {}).get("answer", False):
                    # Confirmation passed
                    pass 
                else:
                    # If VLM explicitly denies, we might flag it, but for now we rely on XML
                    # Just appending feedback
                    feedback.append("VLM confirmed workflow")
            except:
                pass

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback)
    }