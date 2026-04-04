#!/usr/bin/env python3
"""
Verifier for apply_hatch_pattern task.

Verifies:
1. Output DXF exists and is valid.
2. Layer 'CONCRETE_PAD' exists with Red color.
3. ANSI31 Hatch entity exists on the correct layer.
4. Geometry matches expected dimensions (~300x200).
5. Anti-gaming: File created during task & entity count increased.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_apply_hatch_pattern(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata for expected values
    metadata = task_info.get('metadata', {})
    expected_layer = metadata.get('required_layer', 'CONCRETE_PAD')
    expected_color = metadata.get('required_color_index', 1)  # Red
    expected_pattern = metadata.get('required_pattern', 'ANSI31')
    
    # Expected dimensions (350-50 = 300, 250-50 = 200)
    expected_width = 300
    expected_height = 200
    tolerance = metadata.get('bbox_tolerance', 20)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    output_exists = result.get("output_exists", False)
    file_created = result.get("file_created_during_task", False)
    dxf_data = result.get("dxf_analysis", {})
    initial_count = int(result.get("initial_entity_count", 0))
    
    # ----------------------------------------------------------------
    # Criterion 1: File Exists & Valid (15 pts)
    # ----------------------------------------------------------------
    if output_exists and dxf_data.get("valid_dxf", False):
        score += 15
        feedback_parts.append("Valid DXF output found")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file missing or invalid DXF"
        }

    # ----------------------------------------------------------------
    # Criterion 2: Anti-Gaming (Timestamp + Entity Count) (10 pts)
    # ----------------------------------------------------------------
    final_count = dxf_data.get("entity_count", 0)
    if file_created and final_count > initial_count:
        score += 10
        feedback_parts.append(f"New entities added ({initial_count} -> {final_count})")
    elif not file_created:
        feedback_parts.append("FAIL: Output file not created during task (timestamp check)")
    else:
        feedback_parts.append("FAIL: No new entities added to drawing")

    # ----------------------------------------------------------------
    # Criterion 3: Layer Existence & Color (20 pts)
    # ----------------------------------------------------------------
    layers = dxf_data.get("layers", {})
    layer_info = layers.get(expected_layer)
    
    if layer_info:
        score += 10
        feedback_parts.append(f"Layer '{expected_layer}' found")
        
        # Color Check (1 = Red)
        if layer_info.get("color") == expected_color:
            score += 10
            feedback_parts.append("Layer color correct (Red)")
        else:
            feedback_parts.append(f"Layer color mismatch (Found {layer_info.get('color')}, Expected {expected_color})")
    else:
        feedback_parts.append(f"FAIL: Layer '{expected_layer}' not found")

    # ----------------------------------------------------------------
    # Criterion 4: Hatch Pattern (25 pts)
    # ----------------------------------------------------------------
    patterns = dxf_data.get("hatch_patterns", [])
    hatch_layers = dxf_data.get("hatch_layers", [])
    
    hatch_found = False
    pattern_correct = False
    layer_correct = False
    
    if len(patterns) > 0:
        hatch_found = True
        
        # Check if ANSI31 is among them
        if expected_pattern in patterns:
            pattern_correct = True
            
        # Check if any hatch is on the correct layer
        if expected_layer in hatch_layers:
            layer_correct = True
            
    if hatch_found:
        score += 10
        feedback_parts.append("Hatch entity found")
        if pattern_correct:
            score += 10
            feedback_parts.append(f"Pattern '{expected_pattern}' correct")
        else:
            feedback_parts.append(f"Pattern incorrect (Found: {patterns})")
        if layer_correct:
            score += 5
            feedback_parts.append("Hatch on correct layer")
        else:
            feedback_parts.append("Hatch on wrong layer")
    else:
        feedback_parts.append("FAIL: No hatch entities created")

    # ----------------------------------------------------------------
    # Criterion 5: Geometry/Boundary Dimensions (30 pts)
    # ----------------------------------------------------------------
    pad_entities = dxf_data.get("concrete_pad_entities", [])
    rect_found = False
    
    for entity in pad_entities:
        w = entity.get("width", 0)
        h = entity.get("height", 0)
        
        # Check if dimensions match 300x200 within tolerance
        if abs(w - expected_width) <= tolerance and abs(h - expected_height) <= tolerance:
            rect_found = True
            break
            
    if rect_found:
        score += 30
        feedback_parts.append(f"Correct boundary rectangle found (~{expected_width}x{expected_height})")
    else:
        # Partial credit if they made a hatch but we couldn't easily verify the boundary polyline
        # (e.g. if they exploded it or used lines)
        if hatch_found:
            feedback_parts.append("Warning: Exact boundary rectangle not detected as closed polyline (check visual)")
        else:
            feedback_parts.append(f"FAIL: Boundary rectangle ~{expected_width}x{expected_height} not found")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }