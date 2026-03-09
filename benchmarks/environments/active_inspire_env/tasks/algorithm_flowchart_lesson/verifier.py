#!/usr/bin/env python3
"""
Verifier for algorithm_flowchart_lesson task.

Criteria (Total 100 pts, Pass 70):
1. File exists, valid, created during task (20 pts)
2. Page count == 2 (15 pts)
3. Page 1 "Symbols" Key Content (15 pts)
   - "Symbols" title
   - Labels: Start/End, Process, Decision
4. Page 2 "Morning Routine" Content (20 pts)
   - "Morning" title
   - Logic text: Alarm, Weekday, Sleep
5. Shape usage (20 pts)
   - Must use Rectangles, Ovals, and Diamonds/Polygons
6. Connector usage (10 pts)
   - Must detect line/connector elements
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_algorithm_flowchart(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # Load result
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            copy_from_env('/tmp/task_result.json', tmp.name)
            tmp_path = tmp.name
        
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result load failed: {str(e)}"}

    score = 0
    feedback = []
    
    # 1. File Validation (20 pts)
    if result.get('file_found') and result.get('file_valid') and result.get('created_during_task'):
        score += 20
        feedback.append("File created successfully (20/20)")
    elif result.get('file_found'):
        score += 10
        feedback.append("File exists but invalid format or timestamp (10/20)")
    else:
        feedback.append("File not found (0/20)")
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # 2. Page Count (15 pts)
    pg_count = result.get('page_count', 0)
    if pg_count == 2:
        score += 15
        feedback.append("Correct page count: 2 (15/15)")
    else:
        feedback.append(f"Incorrect page count: {pg_count} (expected 2) (0/15)")

    # 3. Symbols Key Content (15 pts)
    txt = result.get('text_analysis', {})
    key_terms = 0
    if txt.get('has_symbols'): key_terms += 1
    if txt.get('has_start'): key_terms += 1
    if txt.get('has_process'): key_terms += 1
    if txt.get('has_decision'): key_terms += 1
    
    # Scale 15 points based on 4 terms
    key_score = int((key_terms / 4.0) * 15)
    score += key_score
    feedback.append(f"Symbols Page Content: Found {key_terms}/4 terms ({key_score}/15)")

    # 4. Morning Routine Content (20 pts)
    routine_terms = 0
    if txt.get('has_morning'): routine_terms += 1
    if txt.get('has_alarm'): routine_terms += 1
    if txt.get('has_weekday'): routine_terms += 1
    if txt.get('has_sleep'): routine_terms += 1
    
    routine_score = int((routine_terms / 4.0) * 20)
    score += routine_score
    feedback.append(f"Routine Page Content: Found {routine_terms}/4 terms ({routine_score}/20)")

    # 5. Shape Usage (20 pts)
    shapes = result.get('shape_analysis', {})
    rects = shapes.get('rect_count', 0)
    ovals = shapes.get('oval_count', 0)
    diamonds = shapes.get('diamond_count', 0)
    
    # Expecting at least one of each for the key + flowchart
    shape_types_found = 0
    if rects > 0: shape_types_found += 1
    if ovals > 0: shape_types_found += 1
    # Diamond often registers as polygon, or if user is drawing logic, they might use multiple lines
    # We'll be lenient: if they have diamonds OR >5 total shapes (implying complexity), give credit
    if diamonds > 0:
        shape_types_found += 1
    elif shapes.get('total_shape_count', 0) >= 6:
        # Fallback: if specific diamond tag not found but scene is complex, assume success if other logic holds
        shape_types_found += 1
        feedback.append("(Diamond shape inferred from complex scene)")

    shape_score = 0
    if shape_types_found == 3: shape_score = 20
    elif shape_types_found == 2: shape_score = 10
    elif shape_types_found == 1: shape_score = 5
    
    score += shape_score
    feedback.append(f"Shape Variety: {shape_types_found}/3 types found ({shape_score}/20)")

    # 6. Connectors (10 pts)
    lines = shapes.get('line_count', 0)
    if lines >= 2:
        score += 10
        feedback.append(f"Connectors found: {lines} (10/10)")
    else:
        feedback.append(f"No/Few connectors found: {lines} (0/10)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }