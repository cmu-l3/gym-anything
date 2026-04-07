#!/usr/bin/env python3
"""
Verifier for Face Inversion Task.

Verification Strategy:
1. XML Analysis: Check if the .psyexp file was created and configured correctly.
   - Crucial: Image component must have 'orientation' set to a variable (e.g., $orientation).
   - Crucial: Keyboard must store correct answer from variable.
2. CSV Analysis: Check if conditions file exists and has correct logic.
   - Must contain 'orientation' column with 0 and 180.
   - Must contain correct mapping: Face->f, House->h.
3. VLM: Visual confirmation of workflow (backup).

Score Breakdown (100 pts):
- Files Exist & Created during task (10 pts)
- Conditions File Structure (Columns) (15 pts)
- Conditions File Content (0/180 present, Face/House present) (15 pts)
- Conditions File Logic (Correct answers map to categories) (10 pts)
- Experiment XML: Image Component uses variable for Image (10 pts)
- Experiment XML: Image Component uses variable for ORIENTATION (20 pts) [Key Skill]
- Experiment XML: Keyboard Config (10 pts)
- Experiment XML: Loop linked (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_face_inversion_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Load result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/face_inversion_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # 1. Files Exist (10 pts)
    if result.get("exp_exists") and result.get("cond_exists"):
        score += 10
        feedback_parts.append("Files created")
    else:
        feedback_parts.append("Missing experiment or conditions file")

    # 2. Conditions File Structure (15 pts)
    if result.get("has_orientation_col") and result.get("has_category_col") and result.get("has_corrans_col"):
        score += 15
        feedback_parts.append("CSV columns correct")
    elif result.get("has_orientation_col"):
        score += 5
        feedback_parts.append("CSV has orientation but missing others")
    else:
        feedback_parts.append("CSV missing required columns (orientation, category, corrAns)")

    # 3. Conditions Content (15 pts)
    content_ok = True
    if not result.get("has_upright"): content_ok = False
    if not result.get("has_inverted"): content_ok = False
    if not result.get("has_faces"): content_ok = False
    
    if content_ok:
        score += 15
        feedback_parts.append("CSV content covers all conditions")
    else:
        feedback_parts.append("CSV missing some conditions (check 0/180 and Face/House)")

    # 4. Conditions Logic (10 pts)
    if result.get("logic_correct") and content_ok:
        score += 10
        feedback_parts.append("Response logic correct")
    elif not result.get("logic_correct"):
        feedback_parts.append("Response logic error (e.g. Face!=f)")

    # 5. XML Image Source (10 pts)
    if result.get("image_uses_var"):
        score += 10
        feedback_parts.append("Image component uses variable")
    else:
        feedback_parts.append("Image component does not use variable source")

    # 6. XML Orientation (20 pts) - CRITICAL SKILL
    if result.get("image_orientation_uses_var"):
        score += 20
        feedback_parts.append("Orientation parameterized correctly")
    else:
        feedback_parts.append("Orientation NOT set to variable (did you type $orientation?)")

    # 7. XML Keyboard (10 pts)
    if result.get("keyboard_stores_correct"):
        score += 10
        feedback_parts.append("Keyboard stores correct answer")
    
    # 8. XML Loop (10 pts)
    if result.get("has_loop") and result.get("loop_file_ref"):
        score += 10
        feedback_parts.append("Loop connected to file")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }