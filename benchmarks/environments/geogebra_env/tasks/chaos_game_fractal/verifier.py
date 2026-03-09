#!/usr/bin/env python3
"""
Verifier for Chaos Game Fractal task.

Scoring (100 points total):
1. File Creation (10 pts): 'chaos_europe.ggb' created during task.
2. Vertices (30 pts): London, Paris, Brussels plotted correctly.
3. Data Volume (30 pts): >500 points generated.
4. Algorithm Validity (30 pts): Points contained within the triangle (Chaos Game property).

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_chaos_game_fractal(traj, env_info, task_info):
    """Verify the Chaos Game fractal construction."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Retrieve Result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving result: {e}"}

    score = 0
    feedback_parts = []
    
    # 2. Evaluate Criteria
    
    # Criterion 1: File Creation (10 pts)
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created successfully (+10)")
    else:
        feedback_parts.append("File not found or not created during task (0/10)")

    # Criterion 2: Vertices (30 pts)
    # 10 pts per correct city
    vertices_found = result.get('vertices_found', 0)
    details = result.get('vertex_details', {})
    
    vertex_score = vertices_found * 10
    score += vertex_score
    
    found_cities = [city for city, data in details.items() if data.get('found')]
    missing_cities = [city for city, data in details.items() if not data.get('found')]
    
    if found_cities:
        feedback_parts.append(f"Vertices found: {', '.join(found_cities)} (+{vertex_score})")
    if missing_cities:
        feedback_parts.append(f"Missing/Incorrect vertices: {', '.join(missing_cities)}")

    # Criterion 3: Data Volume (30 pts)
    # Expecting > 500 points for full score, > 100 for partial
    total_points = result.get('total_points_generated', 0)
    if total_points >= 500:
        score += 30
        feedback_parts.append(f"Fractal generation successful ({total_points} points) (+30)")
    elif total_points >= 100:
        score += 15
        feedback_parts.append(f"Fractal generation partial ({total_points} points) (+15)")
    else:
        feedback_parts.append(f"Insufficient points generated ({total_points} < 100) (0/30)")

    # Criterion 4: Geometric Validity (30 pts)
    # Check if points are inside the triangle (Chaos Game property)
    fraction_inside = result.get('fraction_inside_triangle', 0.0)
    
    if vertices_found == 3 and total_points > 50:
        if fraction_inside > 0.95:
            score += 30
            feedback_parts.append(f"Geometry valid: Points constrained to triangle ({fraction_inside:.1%}) (+30)")
        elif fraction_inside > 0.80:
            score += 15
            feedback_parts.append(f"Geometry mostly valid ({fraction_inside:.1%}) (+15)")
        else:
            feedback_parts.append(f"Geometry invalid: Points scattered outside triangle ({fraction_inside:.1%}) (0/30)")
    elif vertices_found < 3:
        feedback_parts.append("Cannot verify geometry (missing vertices) (0/30)")
    else:
        feedback_parts.append("Cannot verify geometry (insufficient points) (0/30)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }