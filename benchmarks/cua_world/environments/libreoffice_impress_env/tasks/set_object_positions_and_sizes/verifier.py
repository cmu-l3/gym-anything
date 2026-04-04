#!/usr/bin/env python3
"""
Verifier for Set Object Positions and Sizes task.
Analyzes the JSON result exported from the container.
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_positions_and_sizes(traj, env_info, task_info):
    """
    Verify that shapes were positioned and sized correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', {})
    tolerance = metadata.get('tolerance_cm', 0.1)
    
    # Load result from container
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

    # Scoring variables
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Check 1: File Modification (10 pts)
    if result.get("file_modified", False):
        score += 10
        feedback_parts.append("✅ File saved")
    else:
        feedback_parts.append("❌ File not saved/modified")
        return {"passed": False, "score": 0, "feedback": "Task failed: Presentation file was not saved."}

    # Analysis Data
    analysis = result.get("analysis", {})
    if analysis.get("error"):
        return {"passed": False, "score": score, "feedback": f"Error parsing file: {analysis['error']}"}

    shapes_found = analysis.get("shapes_found", {})
    initial_state = result.get("initial_state", {})
    
    # Check 2: Shapes Changed (Anti-gaming) (15 pts)
    # At least one shape must be significantly different from initial state
    changed = False
    for name, initial in initial_state.items():
        current = shapes_found.get(name)
        if current:
            if (abs(current['x'] - initial['x']) > 0.1 or
                abs(current['y'] - initial['y']) > 0.1 or
                abs(current['w'] - initial['w']) > 0.1):
                changed = True
                break
    
    if changed:
        score += 15
        feedback_parts.append("✅ Shapes modified")
    else:
        feedback_parts.append("❌ Shapes match initial state (no changes detected)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check 3: Verify Positions and Sizes (25 pts per shape = 75 pts)
    # Since total is 100, we'll normalize. 10+15=25 base. 75 remaining.
    # 3 shapes -> 25 pts each.
    
    for name, target in targets.items():
        shape_score = 0
        current = shapes_found.get(name)
        
        if not current:
            feedback_parts.append(f"❌ '{name}' not found")
            continue
            
        # Check X (6 pts)
        if abs(current['x'] - target['x']) <= tolerance:
            shape_score += 6
        else:
            feedback_parts.append(f"⚠️ {name} X: {current['x']} (want {target['x']})")

        # Check Y (6 pts)
        if abs(current['y'] - target['y']) <= tolerance:
            shape_score += 6
        else:
            feedback_parts.append(f"⚠️ {name} Y: {current['y']} (want {target['y']})")
            
        # Check Width (6 pts)
        if abs(current['w'] - target['w']) <= tolerance:
            shape_score += 6
        else:
            feedback_parts.append(f"⚠️ {name} W: {current['w']} (want {target['w']})")
            
        # Check Height (7 pts)
        if abs(current['h'] - target['h']) <= tolerance:
            shape_score += 7
        else:
            feedback_parts.append(f"⚠️ {name} H: {current['h']} (want {target['h']})")
            
        score += shape_score
        if shape_score == 25:
            feedback_parts.append(f"✅ {name} correct")

    # Final Verdict
    # Pass threshold: 60 (Base 25 + at least ~35 from shapes, meaning ~1.5 shapes correct)
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }