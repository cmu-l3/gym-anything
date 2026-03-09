#!/usr/bin/env python3
"""
Verifier for deck_framing_plan task.
Evaluates the CAD drawing based on layer structure, geometric accuracy, and adherence to specifications.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deck_framing_plan(traj, env_info, task_info):
    """
    Verify the deck framing plan.
    
    Scoring Criteria:
    1. File validity & Timestamp (15 pts)
    2. Required Layers (15 pts)
    3. Bounding Box Dimensions (10 pts)
    4. Joist Layout & Spacing (25 pts)
    5. Structural Details (Posts/Beam) (15 pts)
    6. Stairs & Dimensions (15 pts)
    7. Overall Complexity (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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

    metrics = result.get('dxf_metrics', {})
    score = 0
    feedback_parts = []
    
    # --- 1. File Validity & Timestamp (15 pts) ---
    if metrics.get('valid_dxf'):
        score += 10
        feedback_parts.append("Valid DXF file created")
        
        if result.get('file_modified_during_task', False):
            score += 5
            feedback_parts.append("File modified during task")
        else:
            feedback_parts.append("WARNING: File not modified during task")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid DXF file found"}

    # --- 2. Required Layers (15 pts) ---
    required_layers = {"OUTLINE", "JOISTS", "BEAM", "POSTS", "STAIRS", "DIMENSIONS"}
    found_layers = set(metrics.get('layers_found', []))
    matched_layers = required_layers.intersection(found_layers)
    
    if len(matched_layers) >= 5:
        score += 15
        feedback_parts.append(f"Layers good ({len(matched_layers)}/6 found)")
    elif len(matched_layers) >= 3:
        score += 7
        feedback_parts.append(f"Layers partial ({len(matched_layers)}/6 found)")
    else:
        feedback_parts.append(f"Layers missing (found {len(matched_layers)})")

    # --- 3. Bounding Box (10 pts) ---
    # Expected deck: 144x192. Stairs add ~48 in negative Y. Dims add padding.
    # Allow loose range.
    bbox = metrics.get('bounding_box', {})
    width = bbox.get('width', 0)
    height = bbox.get('height', 0)
    
    # Width: 144 expected. Range 100-200.
    # Height: 192 deck + 48 stairs = 240. Range 200-300.
    if 100 <= width <= 200 and 180 <= height <= 320:
        score += 10
        feedback_parts.append(f"Dimensions correct (approx {int(width)}x{int(height)})")
    else:
        feedback_parts.append(f"Dimensions off (got {int(width)}x{int(height)})")

    # --- 4. Joist Layout (25 pts) ---
    joist_stats = metrics.get('joist_analysis', {})
    joist_count = joist_stats.get('count', 0)
    std_dev = joist_stats.get('spacing_std_dev', 100)
    
    # 144 / 16 = 9 spaces -> ~10 lines
    if 7 <= joist_count <= 13:
        score += 15
        feedback_parts.append(f"Joist count correct ({joist_count})")
    else:
        feedback_parts.append(f"Joist count incorrect ({joist_count})")
        
    if std_dev < 2.0 and joist_count > 2:
        score += 10
        feedback_parts.append("Joist spacing regular")
    elif std_dev < 5.0 and joist_count > 2:
        score += 5
        feedback_parts.append("Joist spacing slightly irregular")
    else:
        feedback_parts.append("Joist spacing irregular or missing")

    # --- 5. Structural Details (15 pts) ---
    post_count = metrics.get('post_count', 0)
    if post_count >= 2:
        score += 10
        feedback_parts.append("Posts present")
    else:
        feedback_parts.append("Posts missing")
        
    beam_present = "BEAM" in matched_layers and metrics.get("entity_counts", {}).get("BEAM", 0) > 0
    if beam_present:
        score += 5
        feedback_parts.append("Beam present")
        
    # --- 6. Stairs & Dimensions (15 pts) ---
    if metrics.get('stairs_geometry', False):
        score += 10
        feedback_parts.append("Stairs geometry valid")
    elif "STAIRS" in matched_layers:
        score += 5
        feedback_parts.append("Stairs layer exists but geometry unclear")
        
    dim_count = metrics.get('dimension_count', 0)
    if dim_count >= 2:
        score += 5
        feedback_parts.append("Dimensions added")
        
    # --- 7. Complexity (5 pts) ---
    if metrics.get('total_entities', 0) >= 15:
        score += 5
    else:
        feedback_parts.append("Drawing too simple")

    # Final Check
    passed = score >= 60 and metrics.get('valid_dxf')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }