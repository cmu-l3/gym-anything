#!/usr/bin/env python3
"""
Verifier for grease_pencil_line_art_setup task.

Verification Criteria:
1. Output file exists and was modified during task.
2. At least one Grease Pencil object exists in the scene.
3. A 'Line Art' (GP_LINEART) modifier exists on a GP object.
4. The modifier targets the correct collection/object (BMW).
5. Strokes are baked (data contains actual strokes, not just modifier preview).
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_grease_pencil_line_art(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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

    # -----------------------------------------------------------
    # SCORING LOGIC
    # -----------------------------------------------------------
    score = 0
    feedback = []
    
    # 1. File checks (10 pts)
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 10
        feedback.append("Valid output file found.")
    else:
        feedback.append("Output file missing or not saved during task.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    analysis = result.get("analysis", {})
    
    # 2. GP Object Existence (20 pts)
    gp_objs = analysis.get("gp_objects_found", [])
    if gp_objs:
        score += 20
        feedback.append(f"Found {len(gp_objs)} Grease Pencil object(s).")
    else:
        feedback.append("No Grease Pencil objects found in scene.")
    
    # 3. Line Art Modifier (25 pts)
    if analysis.get("has_lineart_modifier"):
        score += 25
        feedback.append("Line Art modifier detected.")
    else:
        feedback.append("No 'Line Art' modifier found on Grease Pencil objects.")

    # 4. Correct Target (20 pts)
    if analysis.get("correct_target"):
        score += 20
        feedback.append("Modifier targets correct object/collection.")
    else:
        # If modifier exists but target wrong, user gets partial credit from step 3
        if analysis.get("has_lineart_modifier"):
             feedback.append("Line Art modifier found, but target is incorrect (expected 'BMW' collection/object).")
    
    # 5. Baked Strokes (25 pts)
    # This prevents 'preview only' gaming. Baked lines create actual stroke data.
    stroke_count = analysis.get("baked_strokes_count", 0)
    if stroke_count > 10:
        score += 25
        feedback.append(f"Line art successfully baked ({stroke_count} strokes).")
    else:
        feedback.append("No baked strokes found. Did you forget to click 'Bake Line Art'?")

    # -----------------------------------------------------------
    # FINAL PASS CHECK
    # -----------------------------------------------------------
    # Threshold: 75 points.
    # Must have GP object + Modifier + Baking (20+25+25 = 70) + File (10) = 80.
    # Target (20) allows for 100.
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": analysis
    }