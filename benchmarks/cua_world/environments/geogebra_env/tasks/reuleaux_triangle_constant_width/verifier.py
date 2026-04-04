#!/usr/bin/env python3
"""
Verifier for Reuleaux Triangle Constant Width Construction task.

Scoring Criteria (100 pts):
- File created during task (15 pts)
- Equilateral triangle vertices correct A, B, C (25 pts)
- 3 Circular Arcs present (25 pts)
- Text annotation 'constant width' present (15 pts)
- File exists and is valid (20 pts)
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reuleaux_triangle_constant_width(traj, env_info, task_info):
    """
    Verify the Reuleaux triangle construction.
    """
    # 1. Setup access to file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function unavailable"}

    # 2. Load Metadata
    metadata = task_info.get('metadata', {})
    tolerance = metadata.get('tolerance', 0.2)
    
    # Expected coordinates
    # A=(0,0), B=(4,0), C=(2, 2*sqrt(3))
    # 2*sqrt(3) approx 3.4641
    targets = [
        (0.0, 0.0),
        (4.0, 0.0),
        (2.0, 3.4641)
    ]

    # 3. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Evaluate Criteria
    score = 0
    feedback = []
    
    # Check 1: File Exists (20 pts)
    if result.get("file_found"):
        score += 20
        feedback.append("File found (+20)")
    else:
        return {"passed": False, "score": 0, "feedback": "File 'reuleaux_triangle.ggb' not found in projects folder."}

    # Check 2: Anti-Gaming / Timestamp (15 pts)
    if result.get("file_created_during_task"):
        score += 15
        feedback.append("File created during session (+15)")
    else:
        feedback.append("File timestamp is too old - must be created during task.")

    # Check 3: Vertices (25 pts)
    points_found = result.get("points_found", [])
    matched_targets = 0
    
    for tx, ty in targets:
        # Look for a point close to this target
        match = False
        for p in points_found:
            px, py = p['x'], p['y']
            dist = math.sqrt((px - tx)**2 + (py - ty)**2)
            if dist <= tolerance:
                match = True
                break
        if match:
            matched_targets += 1
            
    if matched_targets == 3:
        score += 25
        feedback.append("All 3 vertices correct (+25)")
    elif matched_targets > 0:
        partial = int(25 * (matched_targets / 3))
        score += partial
        feedback.append(f"Found {matched_targets}/3 correct vertices (+{partial})")
    else:
        feedback.append("Vertices not found at expected coordinates A(0,0), B(4,0), C(2, 3.46)")

    # Check 4: Circular Arcs (25 pts)
    # Reuleaux triangle requires 3 arcs
    arcs_count = result.get("arcs_found", 0)
    if arcs_count >= 3:
        score += 25
        feedback.append("3+ Circular Arcs found (+25)")
    elif arcs_count > 0:
        partial = int(25 * (arcs_count / 3))
        score += partial
        feedback.append(f"Found {arcs_count}/3 Circular Arcs (+{partial})")
    else:
        feedback.append("No CircularArc commands found. Use 'Circular Arc' tool.")

    # Check 5: Text Annotation (15 pts)
    text_content = result.get("text_found", [])
    has_text = any("constant width" in t.lower() for t in text_content)
    
    # Fallback: check if raw text list contains the string "constant width" (from regex in export script)
    if not has_text and "constant width" in text_content:
        has_text = True
        
    if has_text:
        score += 15
        feedback.append("Text annotation found (+15)")
    else:
        feedback.append("Missing text 'constant width'")

    # Final Verdict
    # Pass threshold: 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }