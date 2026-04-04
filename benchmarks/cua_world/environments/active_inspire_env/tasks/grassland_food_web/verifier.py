#!/usr/bin/env python3
"""
Verifier for Grassland Food Web Flipchart task.

Scoring Criteria (100 points total):
1. File Validity (15 pts): File exists, valid format, created during task.
2. Page Count (10 pts): Exactly 3 pages.
3. Page 1 Content (15 pts):
   - Title "Grassland Food Web" (5 pts)
   - Terms: Producer, Consumer, Decomposer (10 pts)
4. Page 2 Content (40 pts):
   - Organisms (25 pts): Grass, Grasshopper, Frog, Snake/Hawk, Fungi (5 pts each group)
   - Arrows (15 pts): At least 5 line/arrow elements connecting them
5. Page 3 Content (20 pts):
   - Title "Energy Pyramid" (5 pts)
   - Shapes (10 pts): At least 3 stacked shapes
   - Labels (5 pts): Primary/Secondary Consumer text
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_grassland_food_web(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Retrieve result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading results: {str(e)}"}

    score = 0
    feedback = []

    # 1. File Validity (15 pts)
    if result.get('file_found', False) and result.get('file_valid', False):
        if result.get('created_during_task', False):
            score += 15
            feedback.append("File created successfully (15/15)")
        else:
            feedback.append("File exists but was not created during this session (0/15)")
    else:
        feedback.append("File not found or invalid format (0/15)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Page Count (10 pts)
    pages = result.get('page_count', 0)
    if pages == 3:
        score += 10
        feedback.append("Correct page count: 3 (10/10)")
    else:
        feedback.append(f"Incorrect page count: {pages} (expected 3) (0/10)")

    # 3. Page 1 Content (15 pts)
    if result.get('has_title', False):
        score += 5
        feedback.append("Title found (5/5)")
    else:
        feedback.append("Title 'Grassland Food Web' missing (0/5)")
        
    if result.get('has_terms', False):
        score += 10
        feedback.append("Intro terms present (10/10)")
    else:
        feedback.append("Intro terms (Producer/Consumer/Decomposer) missing (0/10)")

    # 4. Page 2 Content (40 pts)
    # Organisms (25 pts total)
    org_score = 0
    if result.get('has_grass', False): org_score += 5
    if result.get('has_grasshopper', False): org_score += 5
    if result.get('has_frog', False): org_score += 5
    if result.get('has_snake_hawk', False): org_score += 5
    if result.get('has_fungi', False): org_score += 5
    score += org_score
    feedback.append(f"Organisms present: {org_score}/25 pts")

    # Arrows (15 pts)
    arrows = result.get('arrow_count', 0)
    if arrows >= 5:
        score += 15
        feedback.append(f"Food web arrows found: {arrows} (15/15)")
    elif arrows > 0:
        score += 5
        feedback.append(f"Few arrows found: {arrows} (5/15)")
    else:
        feedback.append("No arrows/connections found in food web (0/15)")

    # 5. Page 3 Content (20 pts)
    if result.get('has_pyramid_title', False):
        score += 5
        feedback.append("Pyramid title found (5/5)")
    else:
        feedback.append("Pyramid title missing (0/5)")

    shapes = result.get('pyramid_shape_count', 0)
    if shapes >= 3:
        score += 10
        feedback.append(f"Pyramid shapes found: {shapes} (10/10)")
    else:
        feedback.append(f"Pyramid shapes missing/insufficient: {shapes} (0/10)")

    if result.get('has_pyramid_labels', False):
        score += 5
        feedback.append("Pyramid levels labeled (5/5)")
    else:
        feedback.append("Pyramid level labels missing (0/5)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }