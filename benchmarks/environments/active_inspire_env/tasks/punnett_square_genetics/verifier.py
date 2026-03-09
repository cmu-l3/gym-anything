#!/usr/bin/env python3
"""
Verifier for Punnett Square Genetics task.

Scoring Breakdown (100 points total):
- File exists & valid format: 15 pts
- Page count == 4: 10 pts
- Title "Punnett Square": 5 pts
- Terms "dominant" & "recessive": 10 pts
- Parent cross "Bb" indicated: 5 pts
- Grid Rectangles >= 4 (Page 2): 15 pts
- Genotypes BB, Bb, bb present: 15 pts
- Ratios 1:2:1 and 3:1 present: 10 pts
- Practice section text: 5 pts
- Practice rectangles >= 2 (Total rects >= 6): 10 pts

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_punnett_square(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Read result from container
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        
        copy_from_env("/tmp/task_result.json", tmp_path)
        
        with open(tmp_path, 'r') as f:
            result = json.load(f)
            
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification results: {str(e)}"}

    score = 0
    feedback = []

    # 1. File Existence & Validity (15 pts)
    if result.get("file_found", False) and result.get("file_valid", False):
        score += 15
        feedback.append("Valid flipchart file found (+15)")
    elif result.get("file_found", False):
        score += 5
        feedback.append("File found but invalid format (+5)")
    else:
        return {"passed": False, "score": 0, "feedback": "No flipchart file created."}

    # 2. Page Count (10 pts)
    # Exact match required for structure
    pc = result.get("page_count", 0)
    if pc == 4:
        score += 10
        feedback.append("Correct page count (4) (+10)")
    else:
        feedback.append(f"Incorrect page count: {pc} (expected 4)")

    # 3. Title (5 pts)
    if result.get("has_title", False):
        score += 5
        feedback.append("Title found (+5)")
    else:
        feedback.append("Missing title 'Punnett'")

    # 4. Terms (10 pts)
    if result.get("has_terms", False):
        score += 10
        feedback.append("Terms 'dominant/recessive' found (+10)")
    else:
        feedback.append("Missing genetic terms")

    # 5. Parent Cross (5 pts)
    if result.get("has_cross", False):
        score += 5
        feedback.append("Parent cross 'Bb' found (+5)")

    # 6. Genotypes (15 pts)
    if result.get("has_genotypes", False):
        score += 15
        feedback.append("Offspring genotypes (BB, Bb, bb) found (+15)")
    else:
        feedback.append("Missing or incomplete offspring genotypes")

    # 7. Grid Rectangles (15 pts)
    # We check total rectangles. Task asks for 4 grid + 2 practice = 6 total ideally.
    # We allocate 15 pts if at least 4 rectangles exist (implied grid).
    rect_count = result.get("rectangle_count", 0)
    if rect_count >= 4:
        score += 15
        feedback.append(f"Punnett grid shapes detected ({rect_count} rectangles) (+15)")
    else:
        feedback.append(f"Not enough rectangles for grid (found {rect_count}, need 4+)")

    # 8. Ratios (10 pts)
    if result.get("has_ratios", False):
        score += 10
        feedback.append("Ratios 1:2:1 and 3:1 found (+10)")
    else:
        feedback.append("Missing ratio text")

    # 9. Practice Text (5 pts)
    if result.get("has_practice", False):
        score += 5
        feedback.append("Practice section found (+5)")

    # 10. Practice Rectangles (10 pts)
    # If total rectangles >= 6 (4 for grid + 2 for practice)
    if rect_count >= 6:
        score += 10
        feedback.append("Practice boxes detected (+10)")
    elif rect_count >= 4:
        feedback.append("Grid found, but missing practice boxes")
    
    # Check creation time
    if not result.get("created_during_task", False):
        score = 0
        feedback = ["File was not created during this task session (Anti-gaming trigger)."]

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }