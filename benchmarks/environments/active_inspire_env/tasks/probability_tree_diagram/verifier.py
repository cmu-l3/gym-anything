#!/usr/bin/env python3
"""
Verifier for probability_tree_diagram task.

Scoring (100 points total, pass at 70):
1. File Validation (15 pts): File exists, is valid flipchart, created during task.
2. Structure (20 pts): 3 pages (10), Line elements >= 6 (10).
3. Content - Intro (20 pts): Title "Compound Probability" (10), Key terms (10).
4. Content - Tree (35 pts): Heads/Tails labels (10), HH/HT/TH/TT outcomes (15), Probabilities 1/2 & 1/4 (10).
5. Content - Practice (10 pts): "Practice" section with question mark.

Secondary: VLM check on final screenshot to confirm visual structure if programmatic checks are borderline.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot

logger = logging.getLogger(__name__)

def verify_probability_tree_diagram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # 1. Load Programmatic Results
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    score = 0
    feedback = []
    
    # --- Criterion 1: File Validation (15 pts) ---
    if result.get('file_found') and result.get('file_valid'):
        if result.get('created_during_task'):
            score += 15
            feedback.append("File created successfully (15/15)")
        else:
            score += 5
            feedback.append("File exists but timestamp indicates pre-existence (5/15)")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid flipchart file found"}

    # --- Criterion 2: Structure (20 pts) ---
    # Pages
    pg_count = result.get('page_count', 0)
    if pg_count == 3:
        score += 10
        feedback.append("Correct page count (10/10)")
    elif pg_count > 0:
        score += 5
        feedback.append(f"Page count {pg_count} != 3 (5/10)")
    else:
        feedback.append("No pages found (0/10)")

    # Lines (Tree structure)
    lines = result.get('line_count', 0)
    # Also count shapes if lines are missing, assuming user might use thin rectangles
    shapes = result.get('shape_count', 0)
    
    if lines >= 6:
        score += 10
        feedback.append(f"Tree structure lines detected ({lines}) (10/10)")
    elif lines + shapes >= 6:
        # Fallback if they used shapes instead of connector lines
        score += 8
        feedback.append(f"Tree structure shapes detected ({lines+shapes}) (8/10)")
    else:
        feedback.append(f"Missing tree branching lines (found {lines}) (0/10)")

    # --- Criterion 3: Intro Content (20 pts) ---
    if result.get('has_title'):
        score += 10
        feedback.append("Title 'Compound Probability' found (10/10)")
    else:
        feedback.append("Missing title (0/10)")
        
    if result.get('has_terms'):
        score += 10
        feedback.append("Key terms found (10/10)")
    else:
        feedback.append("Missing definitions/terms (0/10)")

    # --- Criterion 4: Tree Content (35 pts) ---
    if result.get('has_coin_labels'):
        score += 10
        feedback.append("Heads/Tails labels present (10/10)")
    else:
        feedback.append("Missing coin flip labels (0/10)")

    if result.get('has_outcomes'):
        score += 15
        feedback.append("Outcome labels (HH/HT/TH/TT) present (15/15)")
    else:
        feedback.append("Missing outcome labels (0/15)")

    if result.get('has_probs'):
        score += 10
        feedback.append("Probability fractions (1/2, 1/4) present (10/10)")
    else:
        feedback.append("Missing probability values (0/10)")

    # --- Criterion 5: Practice (10 pts) ---
    if result.get('has_practice'):
        score += 10
        feedback.append("Practice section found (10/10)")
    else:
        feedback.append("Missing practice problems (0/10)")

    # --- Secondary: VLM Verification (Bonus/Recovery) ---
    # If score is borderline (e.g., 60-69) or lines weren't detected programmatically
    # use VLM to check if it LOOKS like a tree diagram.
    final_img = get_final_screenshot(traj)
    if query_vlm and final_img and (60 <= score < 70 or lines < 6):
        prompt = """
        Analyze this ActivInspire flipchart screenshot.
        Does it show a 'Tree Diagram' (a branching diagram with lines connecting nodes)?
        Does it look like a math lesson about probability?
        Return JSON: {"is_tree_diagram": bool, "is_math_lesson": bool}
        """
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_img)
            parsed = vlm_res.get('parsed', {})
            if parsed.get('is_tree_diagram') and parsed.get('is_math_lesson'):
                score = min(score + 10, 100) # Boost score, max 100
                feedback.append("VLM confirmed visual tree diagram structure (+10 bonus)")
        except Exception:
            pass

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }