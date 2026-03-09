#!/usr/bin/env python3
"""
Verifier for lewis_dot_structure_lesson task.

Scoring System (100 points total):
1. File Mechanics (30 pts):
   - File exists & valid format (15)
   - Created during task (5)
   - Page count = 4 (10)

2. Content Requirements (50 pts):
   - "Lewis" & "Dot" title (5)
   - "Octet" Rule mentioned (10)
   - "Covalent" mentioned (5)
   - Valence/Electron header (5)
   - "H2O" / "Water" example (10)
   - Practice molecules (CO2, NH3, CH4) (10)
   - "Practice" header (5)

3. Visual/Structure (20 pts):
   - Shape count >= 10 (Dots for electrons) (10)
   - VLM verification of dot structures (10)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logger = logging.getLogger(__name__)

def verify_lewis_dot_structure_lesson(traj, env_info, task_info):
    """
    Verify the Lewis Dot Structure lesson flipchart.
    Uses programmatic file analysis and VLM visual verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Load programmatic results
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}

    score = 0
    feedback = []
    
    # --- Programmatic Verification (80 pts max here, +10 for shapes) ---
    
    # File Mechanics
    if result.get('file_found') and result.get('file_valid'):
        score += 15
        feedback.append("File created successfully (15/15)")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid flipchart file found."}

    if result.get('created_during_task'):
        score += 5
        feedback.append("File timestamp valid (5/5)")
    else:
        feedback.append("File appears to be pre-existing (0/5)")

    page_count = result.get('page_count', 0)
    if page_count == 4:
        score += 10
        feedback.append("Correct page count (4) (10/10)")
    else:
        feedback.append(f"Incorrect page count: {page_count} (expected 4) (0/10)")

    # Content Checks
    checks = [
        ('has_title_terms', 5, "Title 'Lewis Dot' found"),
        ('has_octet', 10, "'Octet' rule mentioned"),
        ('has_covalent', 5, "'Covalent' term found"),
        ('has_valence_header', 5, "'Valence/Electron' header found"),
        ('has_water_ex', 10, "Water (H2O) example found"),
        ('has_molecules', 10, "Practice molecules (CO2, NH3, CH4) found"),
        ('has_practice', 5, "'Practice' header found")
    ]

    for key, pts, msg in checks:
        if result.get(key):
            score += pts
            feedback.append(f"{msg} ({pts}/{pts})")
        else:
            feedback.append(f"Missing content: {msg.split(' found')[0]} (0/{pts})")

    # Shape Count (Proxy for dots)
    shape_count = result.get('shape_count', 0)
    if shape_count >= 10:
        score += 10
        feedback.append(f"Sufficient shapes for electron dots ({shape_count}) (10/10)")
    else:
        feedback.append(f"Not enough shapes/dots found ({shape_count}/10) (0/10)")

    # --- VLM Verification (10 pts) ---
    # We want to verify visually that "dots" are around "letters"
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, 3)
        final_ss = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of an ActivInspire lesson creation task.
        The user is supposed to draw "Lewis Dot Structures" (element symbols surrounded by dots).
        
        Look for:
        1. Element symbols (Letters like H, C, N, O).
        2. Small circles or dots drawn surrounding these letters.
        3. A diagram of H2O (Water) showing connections or shared electrons.
        
        Return JSON:
        {
            "dots_around_letters_visible": boolean,
            "water_diagram_visible": boolean,
            "confidence": "high/medium/low"
        }
        """
        
        try:
            # Use final screenshot and one mid-trajectory frame
            images_to_check = [frames[-1]] if frames else []
            if final_ss:
                images_to_check.append(final_ss)
                
            if images_to_check:
                resp = query_vlm(prompt=prompt, images=images_to_check).get('parsed', {})
                
                if resp.get('dots_around_letters_visible'):
                    vlm_score += 5
                    feedback.append("VLM confirmed dots around letters (5/5)")
                
                if resp.get('water_diagram_visible'):
                    vlm_score += 5
                    feedback.append("VLM confirmed water diagram (5/5)")
                    
        except Exception as e:
            feedback.append(f"VLM verification failed: {e}")
            # Grant partial credit if programmatic checks were strong to avoid penalizing VLM error
            if score > 60:
                vlm_score = 5 

    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }