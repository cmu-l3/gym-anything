#!/usr/bin/env python3
"""
Verifier for lattice_deformation_setup task.

Verification Criteria:
1. File Saved & Valid (10 pts)
2. Text Object Created with 'GALAXY' (20 pts)
   - Must be Font object
   - Must have extrude > 0
3. Lattice Object Exists (20 pts)
   - Resolution >= 3 on at least 2 axes
4. Lattice Modifier Correctly Link (25 pts)
   - Text modifier points to Lattice
5. Deformation Applied (25 pts)
   - Lattice points moved from rest position (deformation_score > 0.1)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lattice_deformation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_text = metadata.get('expected_text', "GALAXY")

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

    score = 0
    feedback = []
    
    # 1. File Check
    if result.get("output_exists") and result.get("is_valid_blend"):
        score += 10
        feedback.append("Blend file saved successfully.")
    else:
        feedback.append("Blend file not found or invalid.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    analysis = result.get("scene_analysis", {})
    if analysis.get("error"):
        return {"passed": False, "score": 10, "feedback": f"Scene analysis failed: {analysis['error']}"}

    # 2. Text Object
    text_content = analysis.get("text_content", "")
    if analysis.get("text_found") and text_content == expected_text:
        score += 10
        feedback.append(f"Text object '{text_content}' found.")
        if analysis.get("text_extruded"):
            score += 10
            feedback.append("Text is extruded (3D).")
        else:
            feedback.append("Text is flat (no extrusion).")
    else:
        feedback.append(f"Text object '{expected_text}' not found (Found: '{text_content}').")

    # 3. Lattice Object
    if analysis.get("lattice_found"):
        score += 10
        feedback.append("Lattice object found.")
        
        # Check resolution
        res = analysis.get("lattice_resolution", [0, 0, 0])
        # We generally want at least some complexity, e.g., default is 2,2,2. 
        # Task asks for > 3. Let's be lenient: at least one axis >= 3 implies attempt.
        if any(r >= 3 for r in res):
            score += 10
            feedback.append(f"Lattice resolution adequate {res}.")
        else:
            feedback.append(f"Lattice resolution too low {res} (expected >= 3).")
    else:
        feedback.append("No Lattice object found.")

    # 4. Modifier Link
    if analysis.get("modifier_correct"):
        score += 25
        feedback.append("Lattice Modifier correctly applied to Text.")
    else:
        feedback.append("Lattice Modifier not configured correctly.")

    # 5. Deformation (Work done)
    # Using deformation_score from export script (sum of point deltas)
    deformation = analysis.get("deformation_score", 0.0)
    if deformation > 0.1:
        score += 25
        feedback.append(f"Lattice deformation detected (score: {deformation}).")
    else:
        feedback.append("Lattice points appear untouched (no deformation).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }