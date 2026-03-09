#!/usr/bin/env python3
"""
Verifier for create_spreadsheet_parametric task.

Criteria:
1. File exists and is a valid FCStd created during the task.
2. Spreadsheet object exists with correct aliases (base_length, upright_height, etc).
3. Parameter 'upright_height' is 70 (proving modification), others are default.
4. 3D Geometry (Body/Pad) exists.
5. Expressions link geometry to spreadsheet.
6. Bounding box matches dimensions (60x40x70).
7. VLM verifies workflow (spreadsheet interaction -> sketch -> expressions).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_spreadsheet_parametric(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_aliases = set(metadata.get('required_aliases', []))
    target_values = metadata.get('target_values', {})
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Verification (5 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 5
        feedback_parts.append("File created successfully")
    else:
        return {"passed": False, "score": 0, "feedback": "FCStd file not found or not created during task"}

    inspection = result.get('inspection', {})
    if inspection.get('inspection_error'):
        feedback_parts.append(f"Inspection warning: {inspection['inspection_error']}")

    # 2. Spreadsheet Existence (10 pts)
    if inspection.get('has_spreadsheet'):
        score += 10
        feedback_parts.append("Spreadsheet object found")
    else:
        feedback_parts.append("No Spreadsheet object found")

    # 3. Alias Verification (15 pts)
    found_aliases = set(inspection.get('aliases_found', []))
    missing_aliases = expected_aliases - found_aliases
    if not missing_aliases:
        score += 15
        feedback_parts.append("All parameter aliases found")
    elif found_aliases:
        partial = int(15 * (len(found_aliases) / len(expected_aliases)))
        score += partial
        feedback_parts.append(f"Some aliases missing: {missing_aliases}")
    else:
        feedback_parts.append("No aliases defined")

    # 4. Value Verification (10 pts)
    # upright_height MUST be 70 (proving modification step)
    alias_values = inspection.get('alias_values', {})
    
    val_correct_count = 0
    # Check upright_height specifically (critical step)
    uh_val = alias_values.get('upright_height', 0)
    if abs(uh_val - 70.0) < 0.1:
        score += 5
        val_correct_count += 1
        feedback_parts.append("Parameter 'upright_height' correctly modified to 70")
    elif abs(uh_val - 50.0) < 0.1:
        feedback_parts.append("Parameter 'upright_height' is still 50 (modification step skipped)")
    else:
        feedback_parts.append(f"Parameter 'upright_height' is {uh_val} (expected 70)")

    # Check others (base_length=60, base_width=40, thickness=5)
    other_correct = 0
    if abs(alias_values.get('base_length', 0) - 60) < 0.1: other_correct += 1
    if abs(alias_values.get('base_width', 0) - 40) < 0.1: other_correct += 1
    if abs(alias_values.get('thickness', 0) - 5) < 0.1: other_correct += 1
    
    if other_correct == 3:
        score += 5
        feedback_parts.append("Base parameters correct")
    elif other_correct > 0:
        score += 2
        feedback_parts.append("Some base parameters incorrect")

    # 5. Geometry Existence (10 pts)
    if inspection.get('has_body') and inspection.get('has_pad'):
        score += 10
        feedback_parts.append("L-bracket geometry (Body+Pad) found")
    else:
        feedback_parts.append("Missing Body or Pad feature")

    # 6. Expressions Linking (20 pts)
    expr_count = inspection.get('expression_count', 0)
    if expr_count >= 4:
        score += 20
        feedback_parts.append(f"Parametric expressions active ({expr_count} links)")
    elif expr_count >= 1:
        score += 10
        feedback_parts.append(f"Partial parametric links found ({expr_count})")
    else:
        feedback_parts.append("No expressions found linking Spreadsheet to Geometry")

    # 7. Bounding Box Check (15 pts)
    # Expected approx 60 x 40 x 70
    bbox = inspection.get('bbox')
    bbox_match = False
    if bbox:
        # Sort dimensions to allow for axis swaps
        dims = sorted([float(x) for x in bbox])
        expected = sorted([60.0, 40.0, 70.0])
        
        # Check tolerance (sum of diffs)
        diff = sum(abs(d - e) for d, e in zip(dims, expected))
        if diff < 10.0:  # 10mm total tolerance
            score += 15
            bbox_match = True
            feedback_parts.append("Geometry dimensions match parametric values")
        else:
            feedback_parts.append(f"Geometry dimensions incorrect: {bbox}")
    else:
        feedback_parts.append("Could not determine geometry bounding box")

    # 8. VLM Verification (15 pts)
    # Verify the workflow: Spreadsheet creation -> Sketching -> Expression editor usage
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze this sequence of FreeCAD screenshots. The user is supposed to:
    1. Create a spreadsheet and enter values.
    2. Sketch an L-shape profile.
    3. Use the Expression Editor (often a blue 'f(x)' icon or formula dialog) to link dimensions.
    4. Produce a final 3D L-bracket.
    
    Did the user perform these steps? Specifically look for the Expression Editor dialog or formula entry.
    """
    
    vlm_result = query_vlm(
        images=frames + [final_screen] if final_screen else frames,
        prompt=vlm_prompt
    )
    
    vlm_score = 0
    if vlm_result.get("success"):
        # Simple heuristic or structured output parsing could go here
        # For now, we assume positive sentiment in analysis implies success
        analysis = vlm_result.get("text", "").lower()
        if "expression" in analysis or "formula" in analysis:
            vlm_score += 10
        if "spreadsheet" in analysis:
            vlm_score += 5
            
        feedback_parts.append("VLM verification complete")
    else:
        feedback_parts.append("VLM verification failed")
    
    score += vlm_score

    # Final Pass Logic
    # Must have file, spreadsheet, geometry, and reasonable score
    passed = (score >= 60) and inspection.get('has_spreadsheet') and inspection.get('has_body')

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": ". ".join(feedback_parts)
    }