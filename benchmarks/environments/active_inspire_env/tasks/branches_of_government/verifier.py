#!/usr/bin/env python3
"""
Verifier for Branches of Government Flipchart task.

SCORING CRITERIA (100 points total, 70 to pass):
1. File Verification (30 pts)
   - Exists, valid format, created during task (15 pts)
   - Page count = 3 (15 pts)

2. Content Verification (40 pts)
   - Title & 3 Branches named (15 pts)
   - Detail terms (Congress, Senate, House, President, Supreme Court) (15 pts)
   - Checks & Balances title and examples (10 pts)

3. Visual Structure Verification (30 pts)
   - Shape count >= 6 (Programmatic check) (15 pts)
   - VLM Layout Check (Traj/Screenshot verification) (15 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_branches_of_government(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # 1. Load programmatic result
    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # --- Criterion 1: File & Pages (30 pts) ---
    if result.get('file_found') and result.get('file_valid') and result.get('created_during_task'):
        score += 15
        feedback.append("Valid file created")
    else:
        feedback.append("File missing, invalid, or pre-existing")

    pages = result.get('page_count', 0)
    if pages == 3:
        score += 15
        feedback.append("Correct page count (3)")
    elif pages > 0:
        score += 5
        feedback.append(f"Incorrect page count: {pages} (expected 3)")
    else:
        feedback.append("No pages found")

    # --- Criterion 2: Text Content (40 pts) ---
    # Overview (15 pts)
    branches = result.get('branches_found', {})
    branches_count = sum(1 for v in branches.values() if v)
    has_title = result.get('has_title')
    
    if has_title and branches_count == 3:
        score += 15
        feedback.append("Overview page complete")
    elif branches_count >= 1:
        score += 5 * branches_count
        feedback.append(f"Partial overview ({branches_count}/3 branches)")

    # Details (15 pts)
    details = result.get('details_found', {})
    details_count = sum(1 for v in details.values() if v)
    if details_count == 5:
        score += 15
        feedback.append("All branch details present")
    else:
        score += 3 * details_count
        feedback.append(f"Partial details ({details_count}/5 terms)")

    # Checks (10 pts)
    checks_title = result.get('checks_title')
    examples = result.get('check_examples_count', 0)
    
    if checks_title:
        score += 5
    if examples >= 2:
        score += 5
        feedback.append("Checks and balances section complete")
    elif examples == 1:
        score += 2

    # --- Criterion 3: Visual/Shapes (30 pts) ---
    # Programmatic Shape Count (15 pts)
    shape_count = result.get('shape_count', 0)
    if shape_count >= 6:
        score += 15
        feedback.append(f"Sufficient shapes found ({shape_count})")
    elif shape_count >= 3:
        score += 7
        feedback.append(f"Few shapes found ({shape_count})")
    else:
        feedback.append("Insufficient shapes (diagram missing?)")

    # VLM Verification (15 pts)
    vlm_score = 0
    if query_vlm:
        # Use frames to detect multi-page navigation + final state
        frames = sample_trajectory_frames(traj, 3)
        final_shot = get_final_screenshot(traj)
        if final_shot:
            frames.append(final_shot)
        
        prompt = """
        You are verifying an ActivInspire flipchart task about the US Government.
        Look at these screenshots of the user's workflow.
        
        I need to confirm three things:
        1. Did the user create multiple pages? (Look for page thumbnails or changing content)
        2. Is there a page with colored boxes or columns representing different branches?
        3. Is there a diagram with arrows or connecting lines representing 'checks and balances'?
        
        Answer JSON: {"multi_page_visible": bool, "diagram_visible": bool, "content_quality": "high/medium/low"}
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            if vlm_resp.get('success'):
                parsed = vlm_resp.get('parsed', {})
                if parsed.get('multi_page_visible'):
                    vlm_score += 5
                if parsed.get('diagram_visible'):
                    vlm_score += 10
                feedback.append(f"VLM verification: {parsed}")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            # Fallback if VLM fails but programmatic passed
            if shape_count >= 6 and pages == 3:
                vlm_score += 10 # Give partial credit
    
    score += vlm_score
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback)
    }