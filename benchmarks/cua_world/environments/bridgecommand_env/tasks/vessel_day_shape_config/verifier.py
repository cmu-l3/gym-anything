#!/usr/bin/env python3
"""
Verifier for vessel_day_shape_config task.
Parses the boat.ini file to check for correct day shape configuration.
"""

import json
import os
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vessel_day_shape_config(traj, env_info, task_info):
    """
    Verify that the boat.ini contains the correct ball-diamond-ball configuration
    with proper vertical spacing.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "boat.ini file not found."}
    
    if not result.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "boat.ini was not modified by the agent."}

    content = result.get('content', '')
    
    # Parse the INI content for shapes
    # Expected syntax: Shape(n)="..." and ShapeOffset(n)="x,y,z"
    # We'll use regex to extract all definitions
    
    shapes = {} # Key: index, Value: filename
    offsets = {} # Key: index, Value: (x, y, z)

    # Regex for Shape(n)="filename"
    # Handles quotes and loose spacing
    shape_pattern = re.compile(r'Shape\((\d+)\)\s*=\s*"?([^"\r\n]+)"?', re.IGNORECASE)
    offset_pattern = re.compile(r'ShapeOffset\((\d+)\)\s*=\s*"?([0-9.-]+)\s*,\s*([0-9.-]+)\s*,\s*([0-9.-]+)"?', re.IGNORECASE)

    for line in content.split('\n'):
        line = line.strip()
        
        # Match Shape
        m_shape = shape_pattern.match(line)
        if m_shape:
            idx = int(m_shape.group(1))
            filename = m_shape.group(2).lower() # Normalize to lowercase
            shapes[idx] = filename
            continue
            
        # Match Offset
        m_offset = offset_pattern.match(line)
        if m_offset:
            idx = int(m_offset.group(1))
            x = float(m_offset.group(2))
            y = float(m_offset.group(3))
            z = float(m_offset.group(4))
            offsets[idx] = (x, y, z)
            continue

    # --- Verification Logic ---
    score = 0
    feedback = []

    # 1. Check object count (10 pts)
    if len(shapes) >= 3:
        score += 10
        feedback.append(f"Found {len(shapes)} shapes defined.")
    else:
        feedback.append(f"Found only {len(shapes)} shapes (need 3).")

    # 2. Identify required shapes (20 pts)
    balls = []
    diamonds = []
    
    valid_indices = []
    
    for idx, name in shapes.items():
        if idx in offsets: # Only count if it has a position
            valid_indices.append(idx)
            if 'ball.3ds' in name:
                balls.append(idx)
            elif 'diamond.3ds' in name:
                diamonds.append(idx)

    if len(balls) >= 2 and len(diamonds) >= 1:
        score += 20
        feedback.append("Correct shape models used (2 balls, 1 diamond).")
    else:
        feedback.append(f"Incorrect models: Found {len(balls)} balls, {len(diamonds)} diamonds.")

    # 3. Horizontal Alignment (20 pts)
    # X and Y should be roughly 0.0 and 5.0 (or at least consistent)
    aligned = True
    ref_x, ref_y = 0.0, 5.0
    
    for idx in valid_indices:
        x, y, z = offsets[idx]
        if abs(x - ref_x) > 0.1 or abs(y - ref_y) > 0.1:
            aligned = False
            feedback.append(f"Shape {idx} misalignment: ({x}, {y}) != ({ref_x}, {ref_y})")
    
    if aligned and len(valid_indices) >= 3:
        score += 20
        feedback.append("Horizontal alignment correct.")
    elif len(valid_indices) < 3:
        feedback.append("Horizontal alignment check skipped (insufficient shapes).")
    else:
        feedback.append("Shapes are not horizontally aligned on the mast.")

    # 4. Vertical Arrangement & Spacing (30 pts + 20 pts order)
    # Collect (z, type) tuples
    items = []
    for idx in valid_indices:
        z = offsets[idx][2]
        s_type = "ball" if idx in balls else "diamond" if idx in diamonds else "unknown"
        items.append({'z': z, 'type': s_type, 'idx': idx})

    # Sort by height descending (Top to Bottom)
    items.sort(key=lambda k: k['z'], reverse=True)

    if len(items) >= 3:
        top = items[0]
        mid = items[1]
        bot = items[2]
        
        # Check Order: Ball - Diamond - Ball (20 pts)
        order_correct = (top['type'] == 'ball' and mid['type'] == 'diamond' and bot['type'] == 'ball')
        if order_correct:
            score += 20
            feedback.append("Vertical order correct (Ball-Diamond-Ball).")
        else:
            feedback.append(f"Vertical order incorrect: {top['type']} -> {mid['type']} -> {bot['type']}")

        # Check Spacing (30 pts)
        # Gap 1: Top to Mid
        gap1 = top['z'] - mid['z']
        # Gap 2: Mid to Bot
        gap2 = mid['z'] - bot['z']
        
        spacing_ok = True
        if gap1 < 1.45: # Allow small float tolerance for 1.5
            spacing_ok = False
            feedback.append(f"Top-Mid gap too small: {gap1:.2f}m (min 1.5m)")
        
        if gap2 < 1.45:
            spacing_ok = False
            feedback.append(f"Mid-Bot gap too small: {gap2:.2f}m (min 1.5m)")
            
        if spacing_ok:
            score += 30
            feedback.append(f"Vertical spacing correct (gaps: {gap1:.2f}m, {gap2:.2f}m).")
    else:
        feedback.append("Cannot verify order/spacing (insufficient valid shapes).")

    # Pass logic
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }