#!/usr/bin/env python3
"""
Verifier for rotate_shapes_precise task.

Verifies:
1. File was modified during task (anti-gaming).
2. All 3 expected shapes exist (Controller, DataFlow, IOPort).
3. Each shape is rotated to the correct angle (+/- 7 degrees).
"""

import json
import os
import sys
import tempfile
import math
import re
import logging
import shutil
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utils
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    logger.warning("gym_anything.vlm not available")
    VLM_AVAILABLE = False


def extract_rotation_from_transform(transform_str: str) -> float:
    """
    Extract rotation angle in degrees from ODP draw:transform attribute.
    Format is typically: "rotate (1.5707963267949) translate (2cm 5cm)"
    Rotation is in radians.
    """
    if not transform_str:
        return 0.0
    
    # Regex to find 'rotate ( value )'
    match = re.search(r'rotate\s*\(\s*([-\d\.eE]+)\s*\)', str(transform_str))
    if not match:
        return 0.0
    
    try:
        radians = float(match.group(1))
        degrees = math.degrees(radians)
        
        # Normalize to [0, 360)
        degrees = degrees % 360
        if degrees < 0:
            degrees += 360
            
        return degrees
    except ValueError:
        return 0.0


def angles_match(actual: float, expected: float, tolerance: float) -> bool:
    """Check if angles match within tolerance, handling 0/360 wrapping."""
    diff = abs(actual - expected)
    if diff > 180:
        diff = 360 - diff
    return diff <= tolerance


def parse_odp_shapes(odp_path: str) -> Dict[str, float]:
    """
    Parse ODP file using odfpy and return dict of {shape_name: rotation_degrees}.
    """
    try:
        from odf import opendocument, draw
    except ImportError:
        logger.error("odfpy not installed")
        return {}

    shapes_rotation = {}
    
    try:
        doc = opendocument.load(odp_path)
        
        # Helper to recursively find shapes
        def find_shapes(element):
            # Check if this element is a shape with a name
            if hasattr(element, 'getAttribute'):
                name = element.getAttribute('name')
                if name:
                    transform = element.getAttribute('transform')
                    angle = extract_rotation_from_transform(transform)
                    shapes_rotation[name] = angle
            
            # Recurse children
            if hasattr(element, 'childNodes'):
                for child in element.childNodes:
                    find_shapes(child)
        
        # Start search from all pages
        for page in doc.getElementsByType(draw.Page):
            find_shapes(page)
            
    except Exception as e:
        logger.error(f"Error parsing ODP: {e}")
        
    return shapes_rotation


def verify_rotate_shapes_precise(traj, env_info, task_info):
    """
    Verify that shapes were rotated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    target_shapes = metadata.get('shapes', {
        "Controller": {"expected_angle": 90, "tolerance": 7},
        "DataFlow": {"expected_angle": 45, "tolerance": 7},
        "IOPort": {"expected_angle": 180, "tolerance": 7}
    })

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get execution result JSON
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)

    # Check file modification (Anti-gaming) - 10 pts
    file_modified = result_data.get('file_modified_during_task', False)
    output_exists = result_data.get('output_exists', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Target file not found."}

    if file_modified:
        score += 10
        feedback_parts.append("File modified ✓")
    else:
        feedback_parts.append("File NOT modified (did you save?)")

    # 2. Parse ODP file for shape rotations
    odp_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(result_data['file_path'], odp_temp.name)
        found_shapes = parse_odp_shapes(odp_temp.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse ODP file: {e}"}
    finally:
        if os.path.exists(odp_temp.name):
            os.unlink(odp_temp.name)

    # 3. Verify each shape
    # Points distribution: 30 pts per shape (90 total for shapes)
    # Total possible: 10 + 90 = 100
    
    shapes_correct = 0
    total_shapes = len(target_shapes)
    
    for name, criteria in target_shapes.items():
        expected = criteria['expected_angle']
        tol = criteria['tolerance']
        
        if name not in found_shapes:
            feedback_parts.append(f"Shape '{name}' missing")
            continue
            
        actual = found_shapes[name]
        
        if angles_match(actual, expected, tol):
            score += 30
            shapes_correct += 1
            feedback_parts.append(f"{name}: {actual:.1f}° (Target {expected}°) ✓")
        else:
            feedback_parts.append(f"{name}: {actual:.1f}° (Target {expected}°) ✗")

    # 4. Optional VLM Confirmation (Bonus/Sanity Check)
    if VLM_AVAILABLE and shapes_correct < total_shapes:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            prompt = "Do you see a 'Position and Size' dialog open in LibreOffice Impress with a 'Rotation' tab or angle setting?"
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('answer', False):
                feedback_parts.append("(VLM confirmed dialog usage)")
        except Exception:
            pass

    passed = (file_modified and shapes_correct >= 2) # Pass if saved + at least 2/3 shapes correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }