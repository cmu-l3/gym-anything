#!/usr/bin/env python3
"""
Verifier for Residential Floor Plan task in LibreCAD.

Reads the pre-computed DXF analysis from export_result.sh and scores
based on layer structure, entity counts, geometry, and text content.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


def verify_residential_floor_plan(traj, env_info, task_info):
    """
    Verify the residential floor plan DXF output.

    Scoring (100 points total):
      - File validity and creation timing:     5 pts
      - Layer existence (6 layers):           12 pts
      - Layer colors correct:                  6 pts
      - Wall line segments on WALLS layer:    10 pts
      - Interior wall presence:                8 pts
      - Door arcs on DOORS layer:             12 pts
      - Window lines on WINDOWS layer:         5 pts
      - Kitchen fixtures:                      8 pts
      - Bathroom fixtures:                     7 pts
      - Dimension entities:                   12 pts
      - Room label text:                      10 pts
      - Overall footprint dimensions:          5 pts

    Pass threshold: 60 / 100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    pass_threshold = metadata.get('pass_threshold', 60)
    expected_layers = metadata.get('expected_layers', {})

    score = 0
    feedback = []

    # --- Retrieve result JSON from container ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # --- 1. File validity (5 pts) ---
    if not result_data.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output DXF file was not saved."}

    if not result_data.get('file_created_during_task'):
        feedback.append("File timestamp suggests it was not created during this task session.")
    else:
        score += 5
        feedback.append("DXF file created during task session.")

    analysis = result_data.get('dxf_analysis', {})

    if not analysis.get('valid_dxf'):
        feedback.append(f"Invalid or unparseable DXF: {analysis.get('error', 'unknown')}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # --- 2. Layer existence (12 pts, 2 per layer) ---
    found_layers = analysis.get('layers', {})
    for layer_name in expected_layers:
        if layer_name in found_layers:
            score += 2
            feedback.append(f"Layer {layer_name} exists.")
        else:
            feedback.append(f"Layer {layer_name} MISSING.")

    # --- 3. Layer colors (6 pts, 1 per layer) ---
    for layer_name, exp_color in expected_layers.items():
        if layer_name in found_layers:
            actual_color = found_layers[layer_name].get('color', -1)
            if actual_color == exp_color:
                score += 1
                feedback.append(f"Layer {layer_name} color correct ({exp_color}).")
            else:
                feedback.append(f"Layer {layer_name} wrong color (got {actual_color}, expected {exp_color}).")

    # --- 4. Wall segments on WALLS layer (10 pts) ---
    walls_count = analysis.get('walls_line_count', 0)
    min_walls = metadata.get('min_wall_segments', 12)
    if walls_count >= min_walls:
        score += 10
        feedback.append(f"Sufficient wall segments ({walls_count} >= {min_walls}).")
    elif walls_count >= min_walls // 2:
        score += 5
        feedback.append(f"Partial wall segments ({walls_count}, need {min_walls}).")
    elif walls_count > 0:
        score += 2
        feedback.append(f"Few wall segments ({walls_count}, need {min_walls}).")
    else:
        feedback.append("No wall LINE entities on WALLS layer.")

    # --- 5. Interior wall presence via bounding box (8 pts) ---
    walls_bbox = analysis.get('walls_bbox')
    if walls_bbox:
        w = walls_bbox.get('width', 0)
        h = walls_bbox.get('height', 0)
        tol = metadata.get('tolerance', 1.5)
        ext_w = metadata.get('exterior_width', 30)
        ext_h = metadata.get('exterior_height', 22)
        if abs(w - ext_w) <= tol and abs(h - ext_h) <= tol:
            score += 8
            feedback.append(f"Walls bounding box matches expected footprint ({w:.1f}x{h:.1f}).")
        elif w > 0 and h > 0:
            score += 3
            feedback.append(f"Walls bbox exists but dimensions off ({w:.1f}x{h:.1f}, expected {ext_w}x{ext_h}).")
        else:
            feedback.append("Walls bounding box could not be determined.")
    else:
        feedback.append("No wall geometry found for bounding box check.")

    # --- 6. Door arcs on DOORS layer (12 pts) ---
    arcs_count = analysis.get('doors_arc_count', 0)
    min_arcs = metadata.get('min_door_arcs', 3)
    if arcs_count >= 5:
        score += 12
        feedback.append(f"All door arcs present ({arcs_count}).")
    elif arcs_count >= min_arcs:
        score += 8
        feedback.append(f"Most door arcs present ({arcs_count}/5).")
    elif arcs_count > 0:
        score += 4
        feedback.append(f"Some door arcs present ({arcs_count}/5).")
    else:
        feedback.append("No ARC entities on DOORS layer.")

    # --- 7. Window lines on WINDOWS layer (5 pts) ---
    win_count = analysis.get('windows_line_count', 0)
    if win_count >= 6:
        score += 5
        feedback.append(f"Window lines present ({win_count}).")
    elif win_count >= 2:
        score += 2
        feedback.append(f"Some window lines ({win_count}).")
    else:
        feedback.append("No LINE entities on WINDOWS layer.")

    # --- 8. Kitchen fixtures (8 pts) ---
    fix_count = analysis.get('fixtures_entity_count', 0)
    if fix_count >= 5:
        score += 8
        feedback.append(f"Sufficient fixture entities ({fix_count}).")
    elif fix_count >= 3:
        score += 5
        feedback.append(f"Some fixture entities ({fix_count}).")
    elif fix_count > 0:
        score += 2
        feedback.append(f"Few fixture entities ({fix_count}).")
    else:
        feedback.append("No entities on FIXTURES layer.")

    # --- 9. Bathroom fixtures (7 pts) ---
    # Counted together with kitchen above; give points if enough total
    if fix_count >= 8:
        score += 7
        feedback.append("Likely both kitchen and bathroom fixtures present.")
    elif fix_count >= 5:
        score += 3
        feedback.append("Fixtures present but may be incomplete.")

    # --- 10. Dimension entities (12 pts) ---
    dim_count = analysis.get('dimension_count', 0)
    min_dims = metadata.get('min_dimensions', 8)
    if dim_count >= 10:
        score += 12
        feedback.append(f"Sufficient dimensions ({dim_count} >= 10).")
    elif dim_count >= min_dims:
        score += 8
        feedback.append(f"Most dimensions present ({dim_count}).")
    elif dim_count >= 4:
        score += 4
        feedback.append(f"Some dimensions ({dim_count}).")
    elif dim_count > 0:
        score += 2
        feedback.append(f"Few dimensions ({dim_count}).")
    else:
        feedback.append("No DIMENSION entities found.")

    # --- 11. Room labels (10 pts) ---
    text_contents = analysis.get('text_contents', [])
    all_text = " ".join(t.get('text', '').upper() for t in text_contents)
    required_labels = ["LIVING", "KITCHEN", "BEDROOM", "BATH"]
    labels_found = sum(1 for label in required_labels if label in all_text)
    min_labels = metadata.get('min_room_labels', 4)

    if labels_found >= min_labels:
        score += 10
        feedback.append(f"All required room labels found ({labels_found}/{len(required_labels)}).")
    elif labels_found >= 3:
        score += 7
        feedback.append(f"Most room labels found ({labels_found}/{len(required_labels)}).")
    elif labels_found >= 1:
        score += 3
        feedback.append(f"Some room labels found ({labels_found}/{len(required_labels)}).")
    else:
        feedback.append("No room labels found in text entities.")

    # --- 12. Overall footprint (5 pts) ---
    bbox = analysis.get('bbox')
    if bbox:
        total_w = bbox.get('width', 0)
        total_h = bbox.get('height', 0)
        ext_w = metadata.get('exterior_width', 30)
        ext_h = metadata.get('exterior_height', 22)
        # Allow generous tolerance since arcs/dimensions extend beyond walls
        if total_w >= ext_w * 0.8 and total_h >= ext_h * 0.8:
            score += 5
            feedback.append(f"Overall drawing footprint reasonable ({total_w:.1f}x{total_h:.1f}).")
        else:
            feedback.append(f"Drawing footprint too small ({total_w:.1f}x{total_h:.1f}).")
    else:
        feedback.append("Could not determine overall drawing footprint.")

    # --- Final result ---
    passed = score >= pass_threshold
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
